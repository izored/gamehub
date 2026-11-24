'use strict';
// Controller support (Gamepad API, no dependencies). Loaded after app.js and uses its globals
// (S, $, h, t, toast, render, findGame, toggleFav, openEdit, currentView).
//
//  - Works with every pad the browser reports with the "standard" layout: DualSense, DualShock 4,
//    Xbox and other XInput pads, and the virtual Xbox pad that DS4Windows creates.
//  - All connected pads are merged into one, so a DualShock 4 that Windows sees twice (as itself
//    and through DS4Windows) never acts twice.
//  - Input counts only while the hub's window is in front. Presses meant for a game never reach
//    the hub, and a button still held when you come back is ignored.
//  - The first press after using the mouse only shows where you are; it does nothing else.
//  - View / Share opens an on-screen keyboard for the search box (or the text field in focus).
(() => {
  if (!('getGamepads' in navigator)) return;

  const BTN = { A: 0, B: 1, X: 2, Y: 3, LB: 4, RB: 5, VIEW: 8, MENU: 9, UP: 12, DOWN: 13, LEFT: 14, RIGHT: 15 };
  const DIR = { 12: 'up', 13: 'down', 14: 'left', 15: 'right' };
  const MAPPED = new Set(Object.values(BTN));
  const STICK = 0.5;            // left stick: how far it must travel to count as a direction
  const SCROLL_DEAD = 0.2;      // right stick: dead zone for scrolling the page
  const REPEAT_DELAY = 380;     // ms a direction is held before it repeats
  const REPEAT_EVERY = 110;     // ms between repeats
  const RESUME_QUIET = 600;     // ms of ignored input after the window comes back to the front
  const NAV_H = 64;             // height of the fixed top bar
  const FOCUSABLE = 'a[href], button, input, select, textarea, summary, [tabindex]:not([tabindex="-1"])';
  const SKIP = '.poster button, .arrow, #q, input[type="file"]';   // card buttons have their own controller buttons
  const TEXT = 'input:not([type]), input[type="text"], input[type="search"], textarea';
  const GLYPHS = {
    ps: { A: '✕', B: '○', X: '□', Y: '△', LB: 'L1', RB: 'R1', MENU: '≡', VIEW: 'Share' },
    xbox: { A: 'A', B: 'B', X: 'X', Y: 'Y', LB: 'LB', RB: 'RB', MENU: '≡', VIEW: 'View' },
  };
  // on-screen keyboard: 10 columns; the bottom row's keys cover several columns each
  const KB_ROWS = [
    ['1', '2', '3', '4', '5', '6', '7', '8', '9', '0'],
    ['q', 'w', 'e', 'r', 't', 'y', 'u', 'i', 'o', 'p'],
    ['a', 's', 'd', 'f', 'g', 'h', 'j', 'k', 'l', '-'],
    ['z', 'x', 'c', 'v', 'b', 'n', 'm', '.', ':', '\\'],
    ['SHIFT', 'SPACE', 'DEL', 'DONE'],
  ];
  const KB_SPAN = [0, 0, 1, 1, 1, 1, 2, 2, 3, 3];     // bottom row: column -> key
  const KB_START = [0, 2, 6, 8];                      // bottom row: key -> first column

  const root = document.documentElement;
  const reduced = matchMedia('(prefers-reduced-motion: reduce)');
  const hints = h('div', { class: 'gp-hints', 'aria-hidden': 'true', hidden: true });
  document.body.append(hints);

  let running = false, active = false, resync = true, quietUntil = 0, lastT = 0;
  let prev = new Set(), held = -1, heldAt = 0, lastStep = 0;
  let memory = null, style = 'xbox', warnedLayout = false, hintsFor = null, stickScrolled = false;
  let kb = null;

  const dialog = () => document.querySelector('dialog[open]');
  const behavior = () => (reduced.matches ? 'auto' : 'smooth');
  const hintKey = () => `${style}|${S.q}|${location.hash}|${!!dialog()}|${currentView()}|${kb ? 'kb' + kb.shift : ''}`;

  // ---------------------------------------------------------------- input
  function read() {
    const all = [...navigator.getGamepads()].filter((p) => p && p.connected);
    const pads = all.filter((p) => p.mapping === 'standard');
    if (all.length && !pads.length && !warnedLayout) {
      warnedLayout = true;
      toast(t('gp.layoutWarn'), 'error');
    }
    style = pads.some((p) => /054c|dualsense|dualshock|wireless controller/i.test(p.id)) ? 'ps' : 'xbox';
    const down = new Set();
    let lx = 0, ly = 0, ry = 0;
    for (const p of pads) {
      p.buttons.forEach((b, i) => { if (b.pressed) down.add(i); });
      const [x = 0, y = 0, , v = 0] = p.axes;
      if (Math.abs(x) > Math.abs(lx)) lx = x;
      if (Math.abs(y) > Math.abs(ly)) ly = y;
      if (Math.abs(v) > Math.abs(ry)) ry = v;
    }
    // the left stick works like the D-pad, along its stronger axis
    if (Math.max(Math.abs(lx), Math.abs(ly)) > STICK) {
      down.add(Math.abs(lx) > Math.abs(ly) ? (lx < 0 ? BTN.LEFT : BTN.RIGHT) : (ly < 0 ? BTN.UP : BTN.DOWN));
    }
    return { count: all.length, down, ry };
  }

  function start() {
    if (running) return;
    running = true;
    lastT = performance.now();
    requestAnimationFrame(frame);
  }

  function frame(time) {
    const st = read();
    if (!st.count) { running = false; setActive(false); return; }   // every controller is gone: stop polling
    requestAnimationFrame(frame);
    const dt = Math.min(50, time - lastT);
    lastT = time;
    if (resync || !document.hasFocus() || document.visibilityState !== 'visible') {
      // in the background, or just back in front: whatever is held now counts as already handled
      quietUntil = time + RESUME_QUIET;
      resync = false; prev = st.down; held = -1;
      return;
    }
    if (time < quietUntil) { prev = st.down; held = -1; return; }
    if (kb && !kbAlive()) closeKb();
    if (active) {
      if (!kb) keepFocus();
      // the hints follow focus and dialogs (a dialog opened by a click, a re-render, a route change)
      if (document.activeElement !== (hintsFor && hintsFor.el) || hintKey() !== hintsFor.key) updateHints();
    }
    if (Math.abs(st.ry) > SCROLL_DEAD && !dialog() && !kb) {
      if (!active) setActive(true);
      window.scrollBy(0, st.ry * dt * 1.4);
      stickScrolled = true;
    }
    for (const b of st.down) if (!prev.has(b)) press(b, time);
    const dir = [BTN.UP, BTN.DOWN, BTN.LEFT, BTN.RIGHT].find((b) => st.down.has(b));
    if (dir === undefined) held = -1;
    else if (dir === held && time - heldAt > REPEAT_DELAY && time - lastStep > REPEAT_EVERY) { lastStep = time; move(DIR[dir]); }
    prev = st.down;
  }

  function press(b, time) {
    if (!MAPPED.has(b)) return;              // L2/R2, stick clicks, PS/Guide, touchpad: unused
    if (!active) { wake(); return; }
    if (b in DIR) { held = b; heldAt = lastStep = time; move(DIR[b]); return; }
    if (kb) { kbPress(b); return; }
    const setup = currentView() === 'setup';
    if (b === BTN.A) select();
    else if (b === BTN.B) back();
    else if (b === BTN.X) edit();
    else if (b === BTN.Y) favorite();
    else if (b === BTN.VIEW) { const el = textTarget(); if (el) openKb(el); }
    else if (setup) return;                  // no tabs or Settings before the first scan
    else if (b === BTN.LB) tab(-1);
    else if (b === BTN.RB) tab(1);
    else if (b === BTN.MENU) location.hash = S.route.view === 'settings' && !S.q ? '#/' : '#/settings';
  }

  // ---------------------------------------------------------------- focus
  function setActive(on) {
    if (active === on) return;
    active = on;
    root.classList.toggle('gp', on);
    hints.hidden = !on;
    if (!on) closeKb();
    if (on) updateHints();
  }

  function wake() {
    setActive(true);
    const cur = document.activeElement;
    const el = usable(cur) ? cur : (!dialog() && recall()) || home();
    if (el) go(el); else updateHints();
  }

  function usable(el) {
    if (!el || el === document.body || !el.isConnected || el.disabled || !el.matches(FOCUSABLE) || el.matches(SKIP)) return false;
    const d = dialog();
    if (d ? !d.contains(el) : el.closest('dialog')) return false;
    const r = el.getBoundingClientRect();
    return r.width > 0 && r.height > 0;
  }
  const targets = () => [...(dialog() || document).querySelectorAll(FOCUSABLE)].filter(usable);

  function go(el) {
    stickScrolled = false;
    el.focus({ preventScroll: true });
    reveal(el);
    if (!el.closest('dialog')) memory = keyOf(el);
    updateHints();
  }

  function reveal(el) {
    if (el.closest('#nav')) return;
    if (el.closest('dialog')) { el.scrollIntoView({ block: 'nearest' }); return; }
    if (el.closest('#billboard, .rail[data-row="favorites"]')) { firstScreen(el); return; }
    el.scrollIntoView({ block: 'center', inline: 'nearest', behavior: behavior() });
  }

  // The billboard and the Favorites row share the first screen: moving between them, or along the
  // row, keeps the page at the top so the billboard stays whole. The page only scrolls when the
  // row doesn't fit (a short window), and then just enough to show the card above the hints.
  function firstScreen(el) {
    let top = 0;
    const rail = el.closest('.rail');
    if (rail) {
      railReveal(el, rail);
      const r = el.getBoundingClientRect();
      const limit = innerHeight - (hints.hidden ? 16 : hints.offsetHeight + 34);
      const over = r.bottom + scrollY - limit;
      if (over > 0) top = Math.min(over, r.top + scrollY - NAV_H - 8);
    }
    if (Math.abs(scrollY - top) > 1) window.scrollTo({ top, behavior: behavior() });
  }

  // scroll a row sideways just enough to show the card, inside the row's side padding
  function railReveal(el, rail) {
    const pad = parseFloat(getComputedStyle(rail).scrollPaddingLeft) || 0;
    const rr = rail.getBoundingClientRect(), r = el.getBoundingClientRect();
    const dx = r.left < rr.left + pad ? r.left - rr.left - pad : r.right > rr.right - pad ? r.right - rr.right + pad : 0;
    if (dx) rail.scrollBy({ left: dx, behavior: behavior() });
  }

  // Where focus was, in a form that survives re-rendering: a card by game id (and row), anything
  // else by a path from its nearest ancestor with an id.
  function keyOf(el) {
    const p = el.closest('.poster');
    if (p) { const rail = p.closest('.rail'); return { id: p.dataset.id, row: rail ? rail.dataset.row : null }; }
    const path = [];
    for (let n = el; n && n !== document.body; n = n.parentElement) {
      if (n.id) { path.unshift('#' + CSS.escape(n.id)); return { sel: path.join(' > ') }; }
      path.unshift(`:nth-child(${[...n.parentElement.children].indexOf(n) + 1})`);
    }
    return null;
  }

  function recall() {
    const k = memory;
    if (!k) return null;
    let el;
    if (k.id) {
      const sel = `.poster[data-id="${CSS.escape(k.id)}"]`;
      el = (k.row && document.querySelector(`.rail[data-row="${CSS.escape(k.row)}"] ${sel}`)) || document.querySelector(sel);
    } else {
      el = document.querySelector(k.sel);
    }
    return usable(el) ? el : null;
  }

  // the natural starting point of each view
  function home() {
    const view = currentView();
    const step = '#view-setup .setup-step:not([hidden])';
    const sels = view === 'home' ? ['#billboard .btn-play', '#rows .poster']
      : view === 'grid' ? ['#grid .poster', '#tabs a[aria-current]']
      : view === 'setup' ? [`${step} input:not([disabled])`, `${step} .btn.primary`] : ['#view-settings button'];
    for (const s of sels) { const el = document.querySelector(s); if (usable(el)) return el; }
    return targets()[0] || null;
  }

  // re-rendering (favorites, a launch, a rescan) replaces the cards: put focus back where it was
  function keepFocus() {
    if (dialog() || usable(document.activeElement)) return;
    const el = recall() || home();
    if (!el) return;
    el.focus({ preventScroll: true });
    el.scrollIntoView({ block: 'nearest', inline: 'nearest' });
    memory = keyOf(el);
    updateHints();
  }

  // ---------------------------------------------------------------- spatial navigation
  function move(dir) {
    if (kb) { kbMove(dir); return; }
    const cur = document.activeElement;
    if (!usable(cur)) { const el = recall() || home(); if (el) go(el); return; }
    const r = cur.getBoundingClientRect();
    if (stickScrolled && !cur.closest('#nav, dialog') && (r.bottom < NAV_H || r.top > innerHeight)) {
      // the right stick scrolled it out of sight: continue from what is on screen
      const el = middle();
      if (el) { go(el); return; }
    }
    const next = nearest(cur, dir);
    if (next) go(next);
  }

  function middle() {
    const mid = innerHeight / 2;
    let best = null, bestD = Infinity;
    for (const el of targets()) {
      if (el.closest('#nav')) continue;
      const r = el.getBoundingClientRect();
      if (r.bottom < NAV_H || r.top > innerHeight || r.right < 0 || r.left > innerWidth) continue;
      const d = Math.abs((r.top + r.bottom) / 2 - mid) + Math.max(0, r.left) / 1000;   // ties: leftmost
      if (d < bestD) { bestD = d; best = el; }
    }
    return best;
  }

  function nearest(cur, dir) {
    const d = dialog();
    const inNav = !d && !!cur.closest('#nav');
    const isNav = (el) => !d && !!el.closest('#nav');
    const horizontal = dir === 'left' || dir === 'right';
    const others = targets().filter((el) => el !== cur);
    const a = cur.getBoundingClientRect();
    let pool;
    if (d) pool = others;
    else if (inNav) pool = horizontal ? others.filter(isNav) : dir === 'down' ? others.filter((el) => !isNav(el)) : [];
    else pool = others.filter((el) => !isNav(el));
    let best = pick(pool, a, dir);
    if (!best && !d && !inNav && dir === 'up') {
      // top of the page: up goes to the current tab in the top bar
      const tabEl = document.querySelector('#tabs a[aria-current="page"], #nav-settings[aria-current="page"]');
      best = usable(tabEl) ? tabEl : pick(others.filter(isNav), a, dir);
    }
    return best;
  }

  function pick(pool, a, dir) {
    const ax = (a.left + a.right) / 2, ay = (a.top + a.bottom) / 2;
    const horizontal = dir === 'left' || dir === 'right';
    const found = [];
    for (const el of pool) {
      const b = el.getBoundingClientRect();
      const bx = (b.left + b.right) / 2, by = (b.top + b.bottom) / 2;
      let main, cross;
      if (horizontal) {
        if (dir === 'right' ? bx <= ax + 1 : bx >= ax - 1) continue;
        const overlap = Math.min(a.bottom, b.bottom) - Math.max(a.top, b.top);
        if (overlap < Math.min(a.height, b.height) * 0.3) continue;      // stay on the same row
        main = dir === 'right' ? b.left - a.right : a.left - b.right;
        cross = Math.abs(by - ay);
      } else {
        if (dir === 'down' ? by <= ay + 1 : by >= ay - 1) continue;
        main = dir === 'down' ? b.top - a.bottom : a.top - b.bottom;
        cross = Math.abs(bx - ax) + (b.right < 0 || b.left > innerWidth ? 1e5 : 0);   // cards scrolled out of their row come last
      }
      found.push({ el, main: Math.max(0, main), cross });
    }
    if (!found.length) return null;
    if (horizontal) return found.sort((m, n) => (m.main + m.cross * 2) - (n.main + n.cross * 2))[0].el;
    const first = Math.min(...found.map((f) => f.main));
    return found.filter((f) => f.main <= first + 48).sort((m, n) => m.cross - n.cross)[0].el;   // nearest row, then closest card
  }

  // ---------------------------------------------------------------- actions
  function gameOf(el) {
    if (!el || el === document.body || dialog()) return null;
    const p = el.closest('.poster');
    if (p) return findGame(p.dataset.id);
    if (el.closest('#billboard')) return findGame(document.querySelector('#billboard').dataset.id);   // the game on screen
    return null;
  }

  function select() {
    const el = document.activeElement;
    if (!usable(el)) { wake(); return; }
    if (el.matches(TEXT)) { if (!el.readOnly) openKb(el); return; }
    if (el.matches('select')) {
      // a drop-down cannot be opened from here: each press picks the next choice
      const n = el.options.length;
      if (n) { el.selectedIndex = (el.selectedIndex + 1) % n; el.dispatchEvent(new Event('change', { bubbles: true })); updateHints(); }
      return;
    }
    el.click();
  }

  function back() {
    const d = dialog();
    if (d) { d.close(); return; }
    if (currentView() === 'setup') {
      const b = document.querySelector('#view-setup .setup-step:not([hidden]) .btn.ghost');
      if (b) { b.click(); requestAnimationFrame(() => { const el = home(); if (el) go(el); }); }
      return;
    }
    if (S.q) {
      $('#q').value = ''; S.q = ''; render();
      const el = home(); if (el) go(el);
      return;
    }
    if (S.route.view !== 'home') { location.hash = '#/'; return; }
    window.scrollTo({ top: 0, behavior: behavior() });
    const el = home(); if (el) go(el);
  }

  function edit() { const g = gameOf(document.activeElement); if (g) openEdit(g.id); }

  async function favorite() {
    const g = gameOf(document.activeElement);
    if (!g) return;
    await toggleFav(g);
    updateHints();
  }

  function tab(step) {
    const list = [...document.querySelectorAll('#tabs a')].map((a) => a.getAttribute('href')).concat('#/settings');
    const here = ['', '#', '#/'].includes(location.hash) ? '#/' : location.hash;
    const i = Math.max(0, list.indexOf(here));
    const next = list[Math.max(0, Math.min(list.length - 1, i + step))];
    if (next !== here) location.hash = next;
    else if (S.q) back();
  }

  // ---------------------------------------------------------------- on-screen keyboard
  // the text field it types into: the one in focus, else the search box (not in dialogs or the setup page)
  function textTarget() {
    const el = document.activeElement;
    if (el && el.matches && el.matches(TEXT) && !el.readOnly && !el.disabled && el.getClientRects().length) return el;
    if (dialog() || currentView() === 'setup' || currentView() === 'locked') return null;
    return $('#q');
  }
  const kbAlive = () => kb.el.isConnected && kb.input.isConnected && (!kb.el.closest('dialog') || kb.el.closest('dialog').open);

  function openKb(input) {
    closeKb();
    const keys = h('div', { class: 'osk-keys' });
    const field = h('div', { class: 'osk-field' });
    // inside an open dialog the keyboard must live in the dialog too, or the dialog covers it
    const el = h('div', { class: 'osk', role: 'group', 'aria-label': t('gp.keyboard') }, field, keys);
    (dialog() || document.body).append(el);
    kb = { el, field, keys, input, r: 1, c: 0, shift: false };
    if (input === $('#q')) input.focus({ preventScroll: true });
    kbBuild();
    updateHints();
  }
  function closeKb() {
    if (!kb) return;
    kb.el.remove();
    kb = null;
    updateHints();
  }
  const kbLabel = (k) => ({ SHIFT: '⇧', SPACE: t('gp.space'), DEL: '⌫', DONE: t('gp.done') }[k] || (kb.shift ? k.toUpperCase() : k));
  function kbBuild() {
    kb.keys.replaceChildren(...KB_ROWS.map((row, r) => h('div', { class: 'osk-row' + (r === KB_ROWS.length - 1 ? ' last' : '') },
      row.map((k, c) => h('span', { class: 'osk-key' + (k.length > 1 ? ' wide' : '') + (k === 'SHIFT' && kb.shift ? ' lit' : ''), 'data-r': r, 'data-c': c }, kbLabel(k))))));
    kbPaint();
  }
  function kbIndex() { return kb.r === KB_ROWS.length - 1 ? KB_SPAN[kb.c] : kb.c; }
  function kbPaint() {
    for (const el of kb.keys.querySelectorAll('.osk-key.on')) el.classList.remove('on');
    const cur = kb.keys.querySelector(`.osk-key[data-r="${kb.r}"][data-c="${kbIndex()}"]`);
    if (cur) cur.classList.add('on');
    kb.field.replaceChildren(h('span', {}, kb.input.value), h('i', { class: 'osk-caret' }));
  }
  function kbMove(dir) {
    const last = KB_ROWS.length - 1;
    if (dir === 'up') kb.r = Math.max(0, kb.r - 1);
    else if (dir === 'down') kb.r = Math.min(last, kb.r + 1);
    else if (kb.r === last) {
      const i = Math.max(0, Math.min(KB_START.length - 1, KB_SPAN[kb.c] + (dir === 'left' ? -1 : 1)));
      kb.c = KB_START[i];
    } else kb.c = Math.max(0, Math.min(9, kb.c + (dir === 'left' ? -1 : 1)));
    kbPaint();
  }
  function kbSet(v) {
    kb.input.value = v;
    kb.input.dispatchEvent(new Event('input', { bubbles: true }));
    kbPaint();
  }
  function kbDone() {
    const wasSearch = kb.input === $('#q');
    closeKb();
    if (wasSearch) { const first = document.querySelector('#grid .poster'); if (first && usable(first)) go(first); }
  }
  function kbPress(b) {
    const v = kb.input.value;
    if (b === BTN.A) {
      const k = KB_ROWS[kb.r][kbIndex()];
      if (k === 'SHIFT') { kb.shift = !kb.shift; kbBuild(); updateHints(); }
      else if (k === 'SPACE') kbSet(v + ' ');
      else if (k === 'DEL') kbSet(v.slice(0, -1));
      else if (k === 'DONE') kbDone();
      else {
        kbSet(v + (kb.shift ? k.toUpperCase() : k));
        if (kb.shift) { kb.shift = false; kbBuild(); }   // one capital letter, like a phone keyboard
      }
    }
    else if (b === BTN.X) kbSet(v.slice(0, -1));
    else if (b === BTN.Y) kbSet(v + ' ');
    else if (b === BTN.MENU) kbDone();
    else if (b === BTN.B || b === BTN.VIEW) closeKb();
  }

  // ---------------------------------------------------------------- button hints
  function updateHints() {
    if (!active) return;
    const g = GLYPHS[style];
    const key = (k) => h('span', { class: 'gp-key' + (k.length > 1 ? ' wide' : '') }, k);
    const item = (keys, label) => h('span', { class: 'gp-hint' }, keys.map(key), label);
    const el = document.activeElement;
    const view = currentView();
    const items = [];
    if (kb) {
      items.push(item([g.A], t('gp.type')), item([g.X], t('gp.delete')), item([g.Y], t('gp.space')), item([g.MENU], t('gp.done')), item([g.B], t('gp.close')));
    } else if (dialog()) {
      items.push(item([g.A], el && el.matches && el.matches('select') ? t('gp.change') : t('gp.select')), item([g.B], t('gp.close')));
      if (el && el.matches && el.matches(TEXT)) items.push(item([g.VIEW], t('gp.keyboard')));
    } else if (view === 'setup') {
      items.push(item([g.A], el && el.matches && el.matches('select') ? t('gp.change') : t('gp.select')));
      if (document.querySelector('#view-setup .setup-step:not([hidden]) .btn.ghost')) items.push(item([g.B], t('gp.back')));
    } else {
      const game = gameOf(el);
      items.push(item([g.A], el && el.matches && el.matches('.poster, .btn-play') ? t('gp.play') : el && el.matches && el.matches('select') ? t('gp.change') : t('gp.select')));
      if (game) items.push(item([g.Y], S.favs.has(game.id) ? t('gp.unfavorite') : t('gp.favorite')), item([g.X], t('gp.edit')));
      items.push(item([g.B], S.q ? t('gp.clearSearch') : S.route.view === 'home' ? t('gp.top') : t('gp.home')),
        item([g.VIEW], t('gp.search')), item([g.LB, g.RB], t('gp.tabs')), item([g.MENU], t('gp.settings')));
    }
    hints.replaceChildren(...items);
    hintsFor = { el, key: hintKey() };
  }

  // ---------------------------------------------------------------- wiring
  addEventListener('gamepadconnected', start);
  addEventListener('focus', () => { resync = true; });
  addEventListener('blur', () => { resync = true; });
  document.addEventListener('visibilitychange', () => { resync = true; });
  addEventListener('hashchange', () => {
    memory = null;
    if (kb && kb.input !== $('#q')) closeKb();
    if (active && !kb) requestAnimationFrame(() => { const el = home(); if (el) go(el); });
  });
  // the mouse takes over again as soon as it really moves, clicks or scrolls
  addEventListener('mousemove', (e) => { if (active && Math.abs(e.movementX) + Math.abs(e.movementY) > 2) setActive(false); }, { passive: true });
  addEventListener('mousedown', () => setActive(false), { capture: true, passive: true });
  addEventListener('wheel', () => setActive(false), { passive: true });
  start();   // pads already exposed to this page (for example after a reload)
})();
