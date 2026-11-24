'use strict';

// Where people report problems and wrong translations; www/brand/about.json can name another
let REPO = 'https://github.com/izored/gamehub';
// Launcher names are brand names and stay as they are in every language.
const SOURCES = { steam: 'Steam', epic: 'Epic Games', ea: 'EA', ubisoft: 'Ubisoft', gog: 'GOG', battlenet: 'Battle.net', riot: 'Riot Games', amazon: 'Amazon Games', rockstar: 'Rockstar', xbox: 'Xbox', other: '' };
const SHORT = { steam: 'Steam', epic: 'Epic', ea: 'EA', ubisoft: 'Ubisoft', gog: 'GOG', battlenet: 'Battle.net', riot: 'Riot', amazon: 'Amazon', rockstar: 'Rockstar', xbox: 'Xbox', other: '' };
const VIA = { steam: 'Steam', epic: 'Epic Games Launcher', ea: 'EA app', ubisoft: 'Ubisoft Connect', gog: 'GOG Galaxy', battlenet: 'Battle.net', riot: 'Riot Client', amazon: 'Amazon Games', rockstar: 'Rockstar Games Launcher', xbox: 'Xbox app' };
const I = {
  play: '<svg viewBox="0 0 24 24"><path d="M7 4.5v15l12.5-7.5z"/></svg>',
  star: '<svg viewBox="0 0 24 24"><path d="m12 3.5 2.6 5.3 5.9.9-4.3 4.1 1 5.8-5.2-2.7-5.2 2.7 1-5.8-4.3-4.1 5.9-.9z"/></svg>',
  folder: '<svg viewBox="0 0 24 24"><path d="M3.5 7.5a2 2 0 0 1 2-2h4l2 2h7a2 2 0 0 1 2 2v8a2 2 0 0 1-2 2h-13a2 2 0 0 1-2-2z"/></svg>',
  pen: '<svg viewBox="0 0 24 24"><path d="M4 20h4L19 9a2.8 2.8 0 0 0-4-4L4 16z"/><path d="m13.5 6.5 4 4"/></svg>',
  warn: '<svg viewBox="0 0 24 24"><path d="M12 4 2.8 19.5h18.4z"/><path d="M12 10v4.2"/><path d="M12 17.2v.1"/></svg>',
  left: '<svg viewBox="0 0 24 24"><path d="m15 5-7 7 7 7"/></svg>',
  right: '<svg viewBox="0 0 24 24"><path d="m9 5 7 7-7 7"/></svg>',
  globe: '<svg viewBox="0 0 24 24"><circle cx="12" cy="12" r="9"/><path d="M3 12h18"/><path d="M12 3a14 14 0 0 1 0 18a14 14 0 0 1 0-18z"/></svg>',
  code: '<svg viewBox="0 0 24 24"><path d="m8 7-5 5 5 5"/><path d="m16 7 5 5-5 5"/></svg>',
  message: '<svg viewBox="0 0 24 24"><path d="M4 5.5h16v10H9l-5 4z"/></svg>',
};

const S = {
  catalog: null, favs: new Set(), launches: {}, playtime: {}, covers: new Set(), bust: Date.now(), extra: {},
  q: '', route: { view: 'home' }, settings: null, editId: null, setup: false, locked: false, ds4: null, loadedAt: 0,
};
const $ = (sel) => document.querySelector(sel);
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
// localStorage only remembers small conveniences (sort order, a dismissed note); it may be unavailable
const store = {
  get(k, d) { try { const v = localStorage.getItem('gamehub.' + k); return v == null ? d : v; } catch (e) { return d; } },
  set(k, v) { try { localStorage.setItem('gamehub.' + k, v); } catch (e) { /* private window */ } },
};

// ------------------------------------------------------------------ languages
// www/lang/<code>.json: flat "key": "text" pairs; {name} is filled in, "key.one" / "key.other" (and
// "key.few" / "key.many" where a language needs them) are plural forms. Missing text falls back to English.
const L = { code: 'en', loaded: null, en: {}, cur: {}, list: [{ code: 'en', name: 'English' }] };
const fill = (s, v) => (v ? String(s).replace(/\{(\w+)\}/g, (m, k) => (v[k] != null ? v[k] : m)) : String(s));
const has = (k) => k in L.cur || k in L.en;
function t(key, vars) { return fill(key in L.cur ? L.cur[key] : key in L.en ? L.en[key] : key, vars); }
function pluralOf(dict, code, key, n) {
  let r = 'other';
  try { r = new Intl.PluralRules(code).select(n); } catch (e) { /* unknown locale */ }
  return dict[`${key}.${r}`] != null ? dict[`${key}.${r}`] : dict[`${key}.other`];
}
function tn(key, n, vars) {
  let s = pluralOf(L.cur, L.code, key, n);
  if (s == null) s = pluralOf(L.en, 'en', key, n);
  return fill(s == null ? key : s, Object.assign({ n: fmtNum(n) }, vars));
}
async function getJson(url) { const r = await fetch(url, { cache: 'no-cache' }); if (!r.ok) throw new Error(r.statusText); return r.json(); }
async function loadLangList() { try { const j = await getJson('/lang/index.json'); if (j.languages && j.languages.length) L.list = j.languages; } catch (e) { /* English only */ } }
function resolveLang(pref) {
  const codes = L.list.map((l) => l.code);
  if (pref && pref !== 'auto') return codes.includes(pref) ? pref : 'en';
  for (const raw of navigator.languages || [navigator.language || 'en']) {
    const l = String(raw).toLowerCase();
    const exact = codes.find((c) => c.toLowerCase() === l);
    if (exact) return exact;
    if (/^zh-(tw|hk|mo|hant)/.test(l)) continue;          // Traditional Chinese is not translated yet
    const near = codes.find((c) => c.toLowerCase().split('-')[0] === l.split('-')[0]);
    if (near) return near;
  }
  return 'en';
}
async function setLanguage(pref) {
  S.langPref = pref || 'auto';
  if (!L.en._meta) L.en = await getJson('/lang/en.json').catch(() => ({ _meta: {} }));
  const code = resolveLang(S.langPref);
  if (code === L.loaded) return false;
  L.cur = code === 'en' ? L.en : await getJson(`/lang/${code}.json`).catch(() => L.en);
  L.code = L.cur === L.en ? 'en' : code;
  L.loaded = code;
  document.documentElement.lang = L.code;
  applyI18n();
  return true;
}
// static text in index.html: data-i18n="key" (text) and data-i18n-attr="attr:key,attr:key"
function applyI18n(root = document) {
  for (const el of root.querySelectorAll('[data-i18n]')) el.textContent = t(el.dataset.i18n);
  for (const el of root.querySelectorAll('[data-i18n-attr]')) {
    for (const pair of el.dataset.i18nAttr.split(',')) { const [a, k] = pair.split(':'); el.setAttribute(a.trim(), t(k.trim())); }
  }
}
const langName = (code) => (L.list.find((l) => l.code === code) || { name: code }).name;
function fillLangSelect(sel, value) {
  sel.replaceChildren(h('option', { value: 'auto' }, t('lang.auto', { name: langName(resolveLang('auto')) })),
    ...L.list.map((l) => h('option', { value: l.code }, l.name)));
  sel.value = value || 'auto';
}

// ------------------------------------------------------------------ utils
function h(tag, attrs = {}, ...kids) {
  const el = document.createElement(tag);
  for (const [k, v] of Object.entries(attrs)) {
    if (v == null || v === false) continue;
    if (k === 'class') el.className = v;
    else if (k === 'html') el.innerHTML = v;              // static ICON markup only, never data
    else if (k === 'style') el.style.cssText = v;
    else if (k.startsWith('on')) el.addEventListener(k.slice(2), v);
    else el.setAttribute(k, v === true ? '' : v);
  }
  for (const kid of kids.flat(3)) if (kid != null && kid !== false) el.append(kid);
  return el;
}
const fmtNum = (n) => Number(n || 0).toLocaleString(L.code);
function unit(v, u, digits) {
  try { return new Intl.NumberFormat(L.code, { style: 'unit', unit: u, unitDisplay: 'short', maximumFractionDigits: digits }).format(v); }
  catch (e) { return `${v.toFixed(digits)} ${u}`; }
}
function fmtSize(b) {
  if (!b) return '';
  const gb = b / 1073741824;
  if (gb >= 1000) return unit(gb / 1024, 'terabyte', 1);
  if (gb >= 10) return unit(Math.round(gb), 'gigabyte', 0);
  if (gb >= 1) return unit(gb, 'gigabyte', 1);
  if (b >= 1048576) return unit(Math.round(b / 1048576), 'megabyte', 0);
  return unit(Math.max(1, Math.round(b / 1024)), 'kilobyte', 0);
}
function fmtPlay(min) {
  if (!min) return '';
  if (min < 60) return unit(Math.round(min), 'minute', 0);
  const hrs = min / 60;
  return unit(hrs, 'hour', hrs < 10 ? 1 : 0);
}
function fmtWhen(iso) {
  if (!iso) return '';
  const d = new Date(iso), now = new Date();
  const days = Math.round((new Date(now.toDateString()) - new Date(d.toDateString())) / 86400000);
  if (days < 7) { try { return new Intl.RelativeTimeFormat(L.code, { numeric: 'auto' }).format(-Math.max(0, days), 'day'); } catch (e) { /* below */ } }
  return d.toLocaleDateString(L.code, { day: 'numeric', month: 'short', year: d.getFullYear() === now.getFullYear() ? undefined : 'numeric' });
}
const fmtStamp = (iso) => (iso ? new Date(iso).toLocaleString(L.code, { dateStyle: 'medium', timeStyle: 'short' }) : '');
const norm = (s) => (s || '').toLowerCase().normalize('NFD').replace(/[\u0300-\u036f]/g, '');
const byName = (a, b) => a.name.localeCompare(b.name, L.code, { sensitivity: 'base' });
const ms = (iso) => { const v = iso ? Date.parse(iso) : NaN; return Number.isNaN(v) ? 0 : v; };
// last played: started from the hub, seen by a launcher, or a recorded play session, whichever is newest
function lastPlayed(g) {
  const p = S.playtime[g.id];
  let best = null;
  for (const c of [S.launches[g.id], g.lastPlayed, p && p.last]) if (c && (!best || ms(c) > ms(best))) best = c;
  return best;
}
// play time: Steam already counts its own games (also when started from the hub), so take the larger number
const playMinutes = (g) => Math.max(g.steamMinutes || 0, (S.playtime[g.id] && S.playtime[g.id].minutes) || 0);
const isNew = (g) => (Date.now() - ms(g.installedAt)) / 86400000 <= ((S.catalog && S.catalog.newDays) || 14);
const hue = (s) => [...s].reduce((a, c) => (a * 31 + c.charCodeAt(0)) % 360, 7);
const initials = (s) => s.split(/\s+/).filter((w) => /[a-z0-9]/i.test(w)).slice(0, 2).map((w) => w[0]).join('').toUpperCase();
const library = () => (S.catalog ? S.catalog.games.filter((g) => !g.duplicateOf) : []);
const srcName = (k, short) => ((short ? SHORT : SOURCES)[k] || t('src.standalone'));
// launchers ordered by how many games you have there (no launcher is privileged; standalone games included)
function launcherOrder() {
  const counts = {};
  for (const g of library()) counts[g.source] = (counts[g.source] || 0) + 1;
  return Object.keys(SOURCES).filter((k) => counts[k]).sort((a, b) => counts[b] - counts[a] || srcName(a).localeCompare(srcName(b)));
}
const findGame = (id) => S.catalog && S.catalog.games.find((g) => g.id === id);
const sep = () => h('span', { class: 'dot-sep' }, '·');
const srcTag = (g, long) => h('span', { class: 'src' }, srcName(g.source, !long));
const SORTS = {
  name: byName,
  played: (a, b) => playMinutes(b) - playMinutes(a) || byName(a, b),
  recent: (a, b) => ms(lastPlayed(b)) - ms(lastPlayed(a)) || byName(a, b),
  added: (a, b) => ms(b.installedAt) - ms(a.installedAt) || byName(a, b),
  size: (a, b) => (b.sizeBytes || 0) - (a.sizeBytes || 0) || byName(a, b),
};
S.sort = SORTS[store.get('sort', 'name')] ? store.get('sort', 'name') : 'name';

// artwork: custom upload > downloaded Steam art > Steam's local cache (from the scan)
function artUrl(g, kind) {
  for (const tag of ['.custom', '']) {
    for (const ext of ['jpg', 'png', 'webp']) {
      const f = `${g.id}-${kind}${tag}.${ext}`;
      if (S.covers.has(f)) return `/covers/${encodeURIComponent(f)}?v=${S.bust}`;
    }
  }
  return g[kind] ? `/art/${encodeURIComponent(g[kind])}?v=${S.bust}` : null;
}
const hasCustom = (g, kind) => ['jpg', 'png', 'webp'].some((e) => S.covers.has(`${g.id}-${kind}.custom.${e}`));
const iconUrl = (g) => (g.icon ? `/art/${encodeURIComponent(g.icon)}?v=${S.bust}` : null);

let toastTimer;
function toast(msg, kind = '', sticky = false) {
  const el = $('#toast');
  el.textContent = msg;
  el.className = 'toast show ' + kind;
  clearTimeout(toastTimer);
  if (!sticky) toastTimer = setTimeout(() => { el.className = 'toast ' + kind; }, kind === 'error' ? 6500 : 3200);
}
// server errors carry a code (and one value) so they can be shown in the chosen language
function errText(e) {
  if (e && e.code && has('err.' + e.code)) return t('err.' + e.code, { arg: e.arg || '' });
  return (e && e.message) || String(e);
}

async function call(p, opts) {
  const r = await fetch(p, opts);
  const j = await r.json().catch(() => ({}));
  if (!r.ok) {
    const e = new Error(j.error || r.statusText);
    e.code = j.code; e.arg = j.arg; e.status = r.status;
    if (r.status === 401 && j.code === 'locked') showLocked();
    throw e;
  }
  return j;
}
const api = {
  get: (p) => call(p, { cache: 'no-store' }),
  post: (p, body, raw) => call(p, {
    method: 'POST',
    headers: raw ? { 'X-GameHub': '1', 'Content-Type': raw.type || 'application/octet-stream' } : { 'Content-Type': 'application/json', 'X-GameHub': '1' },
    body: raw || JSON.stringify(body || {}),
  }),
};

async function load() {
  const j = await api.get('/api/games');
  S.extra = j.extra || {};
  S.loadedAt = Date.now();
  await setLanguage(S.extra.language);
  S.playtime = j.playtime || {};
  showBanner(S.extra.notes);
  if (!j.catalog) {
    S.catalog = null;
    if (j.scanning) { await waitForJob(t('setup.scanning')); return j; }
    if (!S.setup) showSetup();
    return j;
  }
  S.setup = false;
  S.catalog = j.catalog;
  S.favs = new Set((j.state && j.state.favorites) || []);
  S.launches = (j.state && j.state.launches) || {};
  S.covers = new Set(j.covers || []);
  render();
  return j;
}
async function waitForJob(msg) {
  if (msg) toast(msg, '', true);
  await sleep(800);
  for (let i = 0; i < 400; i++) {
    const st = await api.get('/api/status').catch(() => ({ scanning: false }));
    if (!st.scanning) break;
    await sleep(1500);
  }
  S.bust = Date.now();
  const had = S.setup;
  await load();
  if (had && S.setup) toast(t('setup.scanFailed'), 'error', true);
}

// a damaged settings file was put back from a backup when the server started
function showBanner(notes) {
  const list = (notes || []).filter(Boolean);
  const b = $('#banner');
  const sig = list.join('|');
  if (!list.length || store.get('banner', '') === sig) { b.hidden = true; return; }
  b.replaceChildren(h('span', {}, t('banner.repaired'), ' ', h('span', { class: 'muted' }, list.join(' '))),
    h('button', { class: 'x', type: 'button', 'aria-label': t('common.close'), onclick: () => { store.set('banner', sig); b.hidden = true; } }, '×'));
  b.hidden = false;
}
function showLocked() {
  S.locked = true;
  for (const v of ['home', 'grid', 'settings', 'setup']) $('#view-' + v).hidden = true;
  $('#nav').hidden = true;
  $('#footer').hidden = true;
  $('#locked').hidden = false;
}

// ------------------------------------------------------------------ pieces
function posterArt(g, forceGen) {
  const cov = !forceGen && artUrl(g, 'cover');
  if (cov) {
    const box = h('div', { class: 'poster-art' });
    box.append(h('img', { class: 'cov', src: cov, alt: '', loading: 'lazy', draggable: 'false', onerror: () => box.replaceWith(posterArt(g, true)) }));
    return box;
  }
  const ic = iconUrl(g);
  return h('div', { class: 'poster-art gen' + (ic ? '' : ' noicon'), style: ic ? `--icon:url("${ic}")` : `--h:${hue(g.name)}` },
    ic ? h('img', { class: 'gen-icon', src: ic, alt: '' }) : h('div', { class: 'gen-initials' }, initials(g.name)),
    h('div', { class: 'gen-title' }, g.name));
}

// 16:9 art for the Favorites row: wide background (hero) with the game's logo on top; Steam's wide
// header already carries the title, so it gets no logo; nothing wide -> generated tile
function wideArt(g, forceGen) {
  const hero = !forceGen && artUrl(g, 'hero');
  const bg = hero || (!forceGen && artUrl(g, 'header'));
  if (!bg) return posterArt(g, true);
  const box = h('div', { class: 'poster-art' });
  box.append(h('img', { class: 'cov', src: bg, alt: '', loading: 'lazy', draggable: 'false', onerror: () => box.replaceWith(wideArt(g, true)) }));
  const logo = hero && artUrl(g, 'logo');
  if (logo) box.append(h('img', { class: 'wide-logo', src: logo, alt: '', draggable: 'false', onerror: (e) => e.target.remove() }));
  return box;
}

function poster(g, wide) {
  const fav = S.favs.has(g.id);
  const played = lastPlayed(g), mins = playMinutes(g);
  const tip = [g.name, g.installDir, played && t('game.lastPlayed', { when: fmtWhen(played) }), mins && t('game.played', { time: fmtPlay(mins) })].filter(Boolean).join('\n');
  const el = h('article', { class: 'poster' + (wide ? ' wide' : ''), tabindex: '0', role: 'button', 'data-id': g.id, 'aria-label': t('game.play', { name: g.name }), title: tip },
    wide ? wideArt(g) : posterArt(g),
    isNew(g) && h('span', { class: 'badge-new' }, t('game.new')),
    h('div', { class: 'poster-hover' },
      h('div', { class: 'ph-top' },
        h('button', { class: 'cbtn pen', type: 'button', title: t('game.editTip'), 'aria-label': t('game.edit', { name: g.name }), html: I.pen,
          onclick: (e) => { e.stopPropagation(); openEdit(g.id); } })),
      h('div', {},
        h('h3', { class: 'ph-name' }, g.name),
        h('div', { class: 'ph-meta' }, srcTag(g), sep(), mins ? fmtPlay(mins) : g.drive, g.sizeBytes ? [sep(), fmtSize(g.sizeBytes)] : null,
          g.warning && h('span', { class: 'warn', title: g.warning, html: I.warn })),
        h('div', { class: 'ph-actions' },
          h('button', { class: 'cbtn play', type: 'button', title: t('game.playShort'), 'aria-label': t('game.play', { name: g.name }), html: I.play, onclick: (e) => { e.stopPropagation(); launch(g, el); } }),
          h('button', { class: 'cbtn' + (fav ? ' on' : ''), type: 'button', title: fav ? t('game.unfav') : t('game.fav'), 'aria-pressed': String(fav), 'aria-label': `${fav ? t('game.unfav') : t('game.fav')}: ${g.name}`, html: I.star, onclick: (e) => { e.stopPropagation(); toggleFav(g); } }),
          h('button', { class: 'cbtn', type: 'button', title: t('game.openFolder'), 'aria-label': `${t('game.openFolder')}: ${g.name}`, html: I.folder, onclick: (e) => { e.stopPropagation(); openFolder({ id: g.id }, g.name); } })))));
  el.addEventListener('click', () => launch(g, el));
  el.addEventListener('keydown', (e) => { if ((e.key === 'Enter' || e.key === ' ') && e.target === el) { e.preventDefault(); launch(g, el); } });
  return el;
}

// key: a stable name (the controller remembers rows by it); title: what is shown
function row(key, title, games, count, wide) {
  if (!games.length) return null;
  const rail = h('div', { class: 'rail', 'data-row': key }, games.map((g) => poster(g, wide)));
  const step = (dir) => rail.scrollBy({ left: dir * rail.clientWidth * 0.85 });
  const left = h('button', { class: 'arrow left', type: 'button', 'aria-label': t('home.scrollLeft', { row: title }), html: I.left, onclick: () => step(-1) });
  const right = h('button', { class: 'arrow right', type: 'button', 'aria-label': t('home.scrollRight', { row: title }), html: I.right, onclick: () => step(1) });
  const upd = () => { left.disabled = rail.scrollLeft < 8; right.disabled = rail.scrollLeft + rail.clientWidth >= rail.scrollWidth - 8; };
  rail.addEventListener('scroll', upd, { passive: true });
  new ResizeObserver(upd).observe(rail); // fires once laid out and on every window resize
  return h('section', { class: 'row' + (wide ? ' row-wide' : '') }, h('h2', { class: 'row-title' }, title, count != null && h('span', { class: 'n' }, fmtNum(count))), left, rail, right);
}

// ------------------------------------------------------------------ views
// Wide background art: the game's hero (yours if you uploaded one), else Steam's wide header
const wideSrc = (g) => artUrl(g, 'hero') || artUrl(g, 'header');
const BRAND = '@brand';   // the Game Hub banner's place in the slideshow
const BANNER = '/brand/banner.svg';   // the banner itself (www/brand/README.md)

// The featured game: the newest install, else the last played, else the first. Games with wide art
// come first; a library with none still gets one, on a blurred version of its cover or icon.
function featured() {
  const all = library();
  const wide = all.filter(wideSrc);
  const lib = wide.length ? wide : all;
  const fresh = lib.filter(isNew).sort(SORTS.added)[0];
  if (fresh) return { g: fresh, why: t('home.whyNew') };
  const rec = lib.filter(lastPlayed).sort(SORTS.recent)[0];
  if (rec) return { g: rec, why: t('home.whyBack') };
  return lib.length ? { g: lib[0], why: t('home.whyLibrary') } : null;
}

// What the billboard shows: the favorite last hovered or focused; with none picked, the slideshow's
// current slide (a game or the Game Hub banner), which starts on the featured game. An empty
// library gets the banner.
function billboardGame() {
  const lib = library();
  const pick = S.bbPick && S.favs.has(S.bbPick) && lib.find((x) => x.id === S.bbPick);
  if (pick) return { g: pick, why: t('home.whyFav') };
  const f = featured();
  if (!f || S.bbSlide === BRAND) return { brand: true };
  const slide = S.bbSlide && S.bbSlide !== f.g.id && lib.find((x) => x.id === S.bbSlide);
  return slide ? { g: slide, why: t('home.whyLibrary') } : f;
}

// ---- idle slideshow: with no favorite picked, the billboard moves through the Game Hub banner
// and every game in the library, one every 2 seconds, in a new shuffled order each round. It holds
// still while the pointer or focus is on the billboard (Play never changes under you), while a
// dialog is open, away from Home, when the page is hidden or scrolled past the billboard, and for
// "reduce motion".
const BB_EVERY = 2000;
const reduceMotion = matchMedia('(prefers-reduced-motion: reduce)');
let bbDeck = [];

function slideshowOn() {
  const bb = $('#billboard');
  if (!S.catalog || bb.hidden || currentView() !== 'home' || document.hidden || reduceMotion.matches) return false;
  if (S.bbPick && S.favs.has(S.bbPick)) return false;
  if (document.querySelector('dialog[open]') || bb.contains(document.activeElement)) return false;
  if (!document.documentElement.classList.contains('gp') && bb.matches(':hover')) return false;   // with a controller, focus decides
  return bb.getBoundingClientRect().bottom > 120;
}

// the id of the next slide (a game id or BRAND); take = move past it
function slideAfter(take) {
  const lib = library();
  if (!lib.length) return null;   // only the banner: nothing to move through
  const ids = new Set(lib.map((g) => g.id)).add(BRAND);
  const cur = $('#billboard').dataset.id;
  for (let round = 0; round < 2; round++) {
    while (bbDeck.length) {
      const id = bbDeck[0];
      if (ids.has(id) && id !== cur) { if (take) bbDeck.shift(); return id; }
      bbDeck.shift();
    }
    // a new round: the banner, then every game in a new order
    const order = lib.map((g) => g.id);
    for (let i = order.length - 1; i > 0; i--) { const j = Math.floor(Math.random() * (i + 1)); [order[i], order[j]] = [order[j], order[i]]; }
    bbDeck = [BRAND, ...order];
  }
  return null;
}

// load the next slide's pictures ahead, so it fades in on time
function preloadSlide(id) {
  const g = id !== BRAND && findGame(id);
  const srcs = g ? [wideSrc(g) || iconUrl(g) || artUrl(g, 'cover'), artUrl(g, 'logo')] : [BANNER];
  for (const src of srcs) { if (src) { const im = new Image(); im.src = src; im.decode().catch(() => {}); } }
}

// the first tick only loads the next pictures; each tick after that shows them and loads the next
let bbArmed = false;
function slideshowTick() {
  setTimeout(slideshowTick, BB_EVERY);
  if (!slideshowOn()) return;
  if (bbArmed) { const id = slideAfter(true); if (id) { S.bbSlide = id; renderBillboard(); } }
  bbArmed = true;
  const next = slideAfter(false);
  if (next) preloadSlide(next);
}
setTimeout(slideshowTick, BB_EVERY);

// Background layers. A new layer fades in over the old one, which goes once it is covered; the same
// picture keeps its layer (no flash on re-render). A picture goes up once it has loaded, so the fade
// never shows an empty frame; onFail runs if it can't load.
let bbTurn = 0;
function showLayer(bb, key, el, onFail) {
  const turn = ++bbTurn;   // also cancels a slower picture still loading
  const layers = bb.querySelectorAll('.bb-layer');
  const top = layers[layers.length - 1];
  if (top && top.dataset.key === key) return;
  el.classList.add('bb-layer');
  el.dataset.key = key;
  if (top) el.classList.add('swap');
  const drop = () => bb.querySelectorAll('.bb-layer').forEach((l) => { if (l.compareDocumentPosition(el) & Node.DOCUMENT_POSITION_FOLLOWING) l.remove(); });
  el.addEventListener('animationend', drop);
  const put = () => {
    if (turn !== bbTurn) return;
    const last = [...bb.querySelectorAll('.bb-layer')].pop();
    if (last) last.after(el); else bb.prepend(el);
    if (getComputedStyle(el).animationName === 'none') drop();   // reduced motion: no fade, no animationend
  };
  if (el.tagName !== 'IMG') { put(); return; }
  el.decode().then(put, () => { if (turn === bbTurn && onFail) onFail(); });
}

// a game's background: its wide art, else a blurred version of its icon or cover
function billboardBg(bb, g, gen) {
  const src = !gen && wideSrc(g);
  if (src) { showLayer(bb, src, h('img', { class: 'bb-bg', alt: '', src }), () => billboardBg(bb, g, true)); return; }
  const ic = iconUrl(g) || artUrl(g, 'cover');
  showLayer(bb, `gen:${g.id}`, h('div', { class: 'bb-gen', style: ic ? `--icon:url("${ic}")` : '' }));
}

function renderBillboard() {
  const bb = $('#billboard');
  const f = billboardGame();
  bb.hidden = false;
  bb.classList.toggle('is-brand', !!f.brand);
  if (f.brand) {
    // the Game Hub banner (www/brand/banner.svg): a slide, or the billboard of an empty library
    showLayer(bb, BRAND, h('img', { class: 'bb-bg bb-brand', alt: '', src: BANNER }));
    const old = bb.querySelector('.bb-content');
    if (old) old.remove();
    bb.dataset.id = BRAND;
    return;
  }
  const g = f.g, logo = artUrl(g, 'logo'), played = lastPlayed(g), mins = playMinutes(g);
  const title = h('h1', { class: 'bb-title' }, g.name);
  const logoEl = logo && h('img', { class: 'bb-logo', src: logo, alt: g.name, onerror: (e) => e.target.replaceWith(title) });
  billboardBg(bb, g);
  const old = bb.querySelector('.bb-content');
  const content = h('div', { class: 'bb-content' + (bb.dataset.id !== g.id ? ' swap' : '') },
      h('div', { class: 'bb-eyebrow' }, h('i'), f.why),
      logoEl || title,
      h('div', { class: 'bb-meta' },
        isNew(g) && h('span', { class: 'pill new' }, t('game.new')),
        srcTag(g, true), sep(), g.drive, g.sizeBytes ? [sep(), fmtSize(g.sizeBytes)] : null,
        sep(), played ? t('game.lastPlayed', { when: fmtWhen(played) }) : t('game.added', { when: fmtWhen(g.installedAt) }),
        mins ? [sep(), t('game.played', { time: fmtPlay(mins) })] : null),
      h('div', { class: 'bb-actions' },
        h('button', { class: 'btn btn-play', type: 'button', html: I.play, onclick: () => launch(g) }, h('span', {}, t('game.playShort'))),
        h('button', { class: 'btn btn-glass', type: 'button', html: I.folder, onclick: () => openFolder({ id: g.id }, g.name) }, h('span', {}, t('game.openFolder'))),
        h('button', { class: 'btn btn-glass btn-round', type: 'button', title: t('common.edit'), 'aria-label': t('game.edit', { name: g.name }), html: I.pen, onclick: () => openEdit(g.id) })));
  if (old) old.replaceWith(content); else bb.append(content);
  bb.dataset.id = g.id;
}

// Hovering or focusing a favorite shows it on the billboard. It stays there after the pointer
// leaves, so the billboard's Play plays the game you were looking at. The short wait keeps a quick
// sweep across the row from flipping through every game. In controller mode the mouse is ignored:
// cards scrolling under a resting pointer would otherwise take over the billboard.
let bbWait, bbNext;
function followFavorites(rail) {
  const pick = (e) => {
    if (e.type === 'mouseover' && document.documentElement.classList.contains('gp')) return;
    const p = e.target.closest('.poster');
    const id = p && p.dataset.id;
    if (!id || id === bbNext) return;
    clearTimeout(bbWait);
    bbNext = id;
    bbWait = setTimeout(() => {
      bbNext = null;
      if (S.bbPick === id && $('#billboard').dataset.id === id) return;
      S.bbPick = id;
      renderBillboard();
    }, 160);
  };
  rail.addEventListener('mouseover', pick);
  rail.addEventListener('focusin', pick);
  const cancel = () => { clearTimeout(bbWait); bbNext = null; };
  rail.addEventListener('mouseleave', cancel);
  // focus leaving the row (say, up to the billboard's Play) must not swap the buttons under it
  rail.addEventListener('focusout', (e) => { if (!rail.contains(e.relatedTarget)) cancel(); });
}

function renderHome() {
  renderBillboard();
  const keep = {};
  document.querySelectorAll('#rows .rail').forEach((r) => { keep[r.dataset.row] = r.scrollLeft; });
  const lib = library();
  const recent = lib.filter(lastPlayed).sort(SORTS.recent).slice(0, 15);
  const most = lib.filter((g) => playMinutes(g) >= 1).sort(SORTS.played).slice(0, 15);
  // Favorites keep the order you starred them in
  const favs = [...S.favs].map((id) => lib.find((g) => g.id === id)).filter(Boolean);
  const added = [...lib].sort(SORTS.added).slice(0, 12);
  const favRow = row('favorites', t('home.favorites'), favs, null, true);
  if (favRow) followFavorites(favRow.querySelector('.rail'));
  const rows = [favRow, row('recent', t('home.continue'), recent),
    row('most', t('home.mostPlayed'), most), row('added', t('home.recentlyAdded'), added),
    ...launcherOrder().map((k) => { const gs = lib.filter((g) => g.source === k).sort(byName); return row('l-' + k, srcName(k), gs, gs.length); })];
  $('#rows').replaceChildren(...rows.filter(Boolean));
  document.querySelectorAll('#rows .rail').forEach((r) => { if (keep[r.dataset.row]) r.scrollLeft = keep[r.dataset.row]; });
  renderDrives();
  renderCleanup();
}

function searchResults() {
  const tokens = norm(S.q).split(/\s+/).filter(Boolean);
  const q = norm(S.q.trim());
  const list = library().filter((g) => tokens.every((tk) => norm(`${g.name} ${srcName(g.source)} ${g.drive} ${g.installDir}`).includes(tk)));
  if (S.sort !== 'name') return list.sort(SORTS[S.sort]);
  return list.sort((a, b) => (norm(b.name).startsWith(q) - norm(a.name).startsWith(q)) || byName(a, b));
}

function renderGridView() {
  let list, title;
  const r = S.route;
  if (S.q) { list = searchResults(); title = t('grid.results', { q: S.q.trim() }); }
  else if (r.source) { list = library().filter((g) => g.source === r.source).sort(SORTS[S.sort]); title = srcName(r.source); }
  else if (r.drive) { list = library().filter((g) => g.drive === r.drive).sort(SORTS[S.sort]); title = t('grid.onDrive', { drive: r.drive }); }
  else { list = library().sort(SORTS[S.sort]); title = t('grid.all'); }
  $('#grid-sort').value = S.sort;
  $('#grid-title').replaceChildren(title, ' ', h('span', { class: 'muted', style: 'font-size:.6em;font-weight:500' }, fmtNum(list.length)));
  $('#grid').replaceChildren(...list.map((g) => poster(g)));
  $('#empty').hidden = list.length > 0;
}

function renderDrives() {
  $('#drives').replaceChildren(...S.catalog.drives.filter((d) => d.games > 0).map((d) => {
    const pct = (x) => Math.max(0, Math.min(100, (x / d.totalBytes) * 100));
    return h('button', { class: 'drive', type: 'button', title: t('home.driveTip', { drive: d.letter }), onclick: () => { location.hash = `#/d/${d.letter[0]}`; } },
      h('div', { class: 'drive-head' }, h('span', { class: 'drive-letter' }, d.letter), h('span', { class: 'drive-label' }, d.label || t('drives.localDisk')),
        h('span', { class: 'drive-games' }, tn('n.games', d.games))),
      h('div', { class: 'bar' }, h('i', { class: 'g', style: `width:${pct(d.gameBytes)}%` }), h('i', { class: 'o', style: `width:${pct(d.totalBytes - d.freeBytes - d.gameBytes)}%` })),
      h('div', { class: 'drive-foot' }, h('span', {}, t('home.ofGames', { size: fmtSize(d.gameBytes) })), h('span', {}, t('home.free', { size: fmtSize(d.freeBytes) }))));
  }));
}

function renderCleanup() {
  const games = S.catalog.games;
  const items = [
    ...games.filter((g) => g.duplicateOf).map((g) => {
      const keep = findGame(g.duplicateOf);
      return { title: t('cleanup.extraCopy', { name: g.name, launcher: srcName(g.source, true), drive: g.drive }), path: g.installDir, sizeBytes: g.sizeBytes, note: g.note, keep: keep && keep.installDir, id: g.id };
    }),
    ...(S.catalog.cleanup || []),
  ];
  $('#cleanup').hidden = !items.length;
  if (!items.length) return;
  const total = items.reduce((a, i) => a + (i.sizeBytes || 0), 0);
  $('#cleanup-title').textContent = `${t('home.cleanup')} · ${tn('n.items', items.length)}`;
  $('#cleanup-sub').textContent = t('home.reclaimable', { size: fmtSize(total) });
  $('#cleanup-list').replaceChildren(...items.map((i) => h('li', {},
    h('div', { class: 'c-title' }, i.title), h('div', { class: 'c-size' }, fmtSize(i.sizeBytes)),
    h('div', { class: 'c-path' }, i.path), i.keep && h('div', { class: 'c-keep' }, t('cleanup.keep', { path: i.keep })), i.note && h('div', { class: 'c-note' }, i.note),
    h('div', { class: 'c-act' }, h('button', { class: 'btn small', type: 'button', onclick: () => openFolder(i.id ? { id: i.id } : { path: i.path }, i.title) }, t('game.openFolder'))))));
}

// "Never read" drive list, used by the setup page and Settings > Drives; ex is a Set of letters
function drivePicker(ul, drives, ex) {
  const kind = (d) => (d.system ? t('drives.windows') : d.usb ? t('drives.usb') : t('drives.' + (['removable', 'network', 'optical', 'fixed'].includes(d.type) ? d.type : 'otherType')));
  ul.replaceChildren(...drives.filter(Boolean).map((d) => {
    const cb = h('input', { type: 'checkbox', class: 'switch', checked: ex.has(d.letter), disabled: d.system, 'aria-label': t('drives.neverReadOn', { drive: d.letter }) });
    cb.addEventListener('change', () => { if (cb.checked) ex.add(d.letter); else ex.delete(d.letter); });
    return h('li', {}, h('label', { class: 'drive-row' + (d.system ? ' locked-row' : '') },
      h('span', { class: 'drive-letter' }, d.letter),
      h('span', { class: 'dr-info' }, h('span', { class: 'dr-label' }, d.label || t('drives.localDisk')), h('span', { class: 'dr-meta' }, [kind(d), fmtSize(d.sizeBytes)].filter(Boolean).join(' · '))),
      h('span', { class: 'dr-never' }, d.system ? t('drives.alwaysRead') : t('drives.neverRead')), cb));
  }));
}

// one folder with its check result; ok folders can be ticked, the others say why not
const statusText = (f) => t('check.' + f.status, { launcher: f.launcher || '' });
function folderCheckRow(f, onChange) {
  const ok = f.status === 'ok';
  const cb = h('input', { type: 'checkbox', checked: ok && f.on, disabled: !ok, 'aria-label': f.path });
  cb.addEventListener('change', () => { f.on = cb.checked; if (onChange) onChange(); });
  return h('li', { class: ok ? '' : 'bad' }, h('label', { class: 'fcheck' }, cb, h('span', { title: f.path }, f.path), !ok && h('em', {}, statusText(f))));
}

async function renderSettings() {
  const lib = library();
  $('#set-scan').textContent = t('settings.scanDesc', { games: tn('n.games', lib.length), date: fmtStamp(S.catalog.generatedAt) });
  const withCover = lib.filter((g) => artUrl(g, 'cover')).length;
  $('#set-covers').textContent = t('settings.coversDesc', { n: fmtNum(withCover), total: fmtNum(lib.length) });
  let st;
  try { st = S.settings = await api.get('/api/settings'); } catch (e) { toast(t('err.settings', { msg: errText(e) }), 'error'); return; }
  st.gameRoots = (st.gameRoots || []).filter(Boolean);
  st.excluded = (st.excluded || []).filter(Boolean);
  const roots = st.gameRoots;
  $('#folders').replaceChildren(...(roots.length ? roots.map((r) => h('li', {}, h('span', { title: r }, r),
    h('button', { class: 'x', type: 'button', 'aria-label': t('settings.removeFolder', { path: r }), onclick: () => saveRoots(roots.filter((x) => x !== r)) }, t('common.remove'))))
    : [h('li', { class: 'empty-li' }, t('settings.noFolders'))]));
  S.setEx = new Set(st.excluded);
  drivePicker($('#set-drives'), st.drives || [], S.setEx);
  const labels = (st.excludedLabels || []).filter(Boolean);
  $('#set-drives-note').textContent = labels.length ? t('settings.drivesLabels', { labels: labels.join(', ') }) : '';
  const hidden = (st.hidden || []).filter(Boolean);
  $('#hidden-list').replaceChildren(...(hidden.length
    ? hidden.map((x) => h('li', {}, h('span', {}, x.name), h('button', { class: 'x', type: 'button', onclick: () => unhide(x) }, t('settings.showAgain'))))
    : [h('li', { class: 'empty-li' }, t('settings.noHidden'))]));
  $('#set-startup').checked = !!st.startup;
  $('#set-minimize').checked = st.minimizeOnLaunch !== false;
  $('#set-restore').checked = st.restoreAfterGame !== false;
  $('#set-track').checked = !!st.trackOutsideLaunches;
  $('#set-summon').checked = st.controllerSummon !== false;
  $('#set-lock').checked = !!st.lockToAccount;
  $('#security-card').hidden = !((st.otherAccounts || []).filter(Boolean).length || st.lockToAccount);
  fillLangSelect($('#set-language'), st.language);
  renderLangNote();
  renderBackups();
  renderAbout();
  renderDs4(st);
}

// ---- Settings › Made by: who made Game Hub and where to find them, from www/brand/about.json so a
// fork can swap it. Only https: links (and mailto: for feedback) are used.
const safeHref = (u, ...schemes) => { try { const x = new URL(u); return schemes.includes(x.protocol) ? x.href : null; } catch (e) { return null; } };
async function loadAbout() {
  try { S.about = await (await fetch('/brand/about.json', { cache: 'no-cache' })).json(); } catch (e) { S.about = {}; }
  const repo = safeHref(S.about.repo, 'https:');
  if (repo) REPO = repo.replace(/\/+$/, '');
}

function renderAbout() {
  const a = S.about || {};
  $('#about-name').textContent = a.name || 'Game Hub';
  $('#about-role').textContent = [a.role, 'Game Hub'].filter(Boolean).join(' · ');
  // a mail link opens the mail app in place; web links open in the browser
  const out = (label, href, icon, cls) => href && h('a', Object.assign({ class: cls || 'btn small', href, html: icon },
    href.startsWith('mailto:') ? {} : { target: '_blank', rel: 'noopener noreferrer' }), h('span', {}, label));
  const site = safeHref(a.website, 'https:');
  $('#about-links').replaceChildren(...[site && out(new URL(site).host, site, I.globe, 'btn small ghost'), out('GitHub', REPO, I.code, 'btn small ghost')].filter(Boolean));
  $('#about-actions').replaceChildren(...[out(t('about.star'), REPO, I.star, 'btn small primary'),
    out(t('about.feedback'), safeHref(a.feedback, 'https:', 'mailto:'), I.message), out(t('about.bug'), `${REPO}/issues/new/choose`, I.warn)].filter(Boolean));
  $('#about-version').textContent = [a.version && t('about.version', { version: a.version }), a.license && t('about.license', { license: a.license })].filter(Boolean).join(' · ');
}

function renderLangNote() {
  const cur = L.list.find((l) => l.code === L.code);
  const link = (label, href) => h('a', { href, target: '_blank', rel: 'noopener' }, label);
  $('#set-language-note').replaceChildren(...(cur && cur.machine
    ? [t('lang.aiNote'), ' ', link(t('lang.report'), `${REPO}/issues/new?template=translation.yml`)]
    : [t('lang.enNote'), ' ', link(t('lang.howTo'), `${REPO}/blob/main/docs/translating.md`)]));
}

async function renderBackups() {
  let b;
  try { b = await api.get('/api/backups'); } catch (e) { $('#backup-list').replaceChildren(h('li', { class: 'empty-li' }, errText(e))); return; }
  const reason = (r) => ({ daily: t('backups.reasonDaily'), manual: t('backups.reasonManual'), 'before restore': t('backups.reasonRestore') }[r] || r || '');
  const list = (b.backups || []).filter(Boolean).sort((x, y) => ms(y.created) - ms(x.created)).slice(0, 12);
  $('#backup-list').replaceChildren(...(list.length ? list.map((x) => h('li', {},
    h('span', {}, fmtStamp(x.created)), h('em', {}, [reason(x.reason), fmtSize(x.sizeBytes)].filter(Boolean).join(' · ')),
    h('button', { class: 'x', type: 'button', onclick: () => restoreBackup(x) }, t('backups.restore'))))
    : [h('li', { class: 'empty-li' }, t('backups.none'))]));
  $('#data-folder').textContent = b.data ? t('backups.dataFolder', { path: b.data }) : '';
  $('#backup-copy-to').textContent = b.copyTo || t('backups.copyToNone');
  $('#btn-backup-copy-clear').hidden = !b.copyTo;
}

// DS4Windows (only shown when it is installed): what it does while each game runs. pad-advice.js turns
// what each game understands by itself ("Check my games"), your controllers and your answers into suggestions.
async function ensureDs4(force) {
  if (S.ds4 && !force) return S.ds4;
  try { S.ds4 = await api.get('/api/ds4windows'); } catch (e) { S.ds4 = { found: false, profiles: [], games: {} }; }
  const d = S.ds4;
  d.games = d.games || {}; d.facts = d.facts || {}; d.feedback = d.feedback || {};
  d.profiles = [].concat(d.profiles || []).filter(Boolean);   // one profile may arrive as a plain string
  d.pads = [].concat(d.pads || []).filter(Boolean);
  return d;
}
function ds4Options(sel, value) {
  sel.replaceChildren(h('option', { value: 'on' }, t('ds4.on')), h('option', { value: 'off' }, t('ds4.off')),
    ...S.ds4.profiles.map((p) => h('option', { value: 'profile:' + p }, t('ds4.profile', { name: p }))));
  sel.value = value || 'on';
  if (sel.value !== (value || 'on')) sel.value = 'on';
}
const ruleOf = (r) => (r === 'off' ? 'off' : 'on');           // a profile still means DS4Windows is on
const PAD_NAME = { ds4: 'ds4.pad.ds4', dualsense: 'ds4.pad.dualsense' };
const PAD_LINK = { bt: 'ds4.link.bt', usb: 'ds4.link.usb', none: 'ds4.link.none' };
const PAD_HOW = { now: 'ds4.how.now', paired: 'ds4.how.paired', seen: 'ds4.how.seen', missing: 'ds4.how.missing' };
const WHY = { native: 'ds4.why.native', cableOnly: 'ds4.why.cableOnly', xboxOnly: 'ds4.why.xboxOnly', steamInput: 'ds4.why.steamInput',
  steamTranslates: 'ds4.why.steamTranslates', unknown: 'ds4.why.unknown', youDouble: 'ds4.why.youDouble', youFineOff: 'ds4.why.youFineOff', youFineOn: 'ds4.why.youFineOn',
  youNone: 'ds4.why.youNone', youNoneOn: 'ds4.why.youNoneOn', noPads: 'ds4.why.noPads', notWrapped: 'ds4.why.notWrapped' };
const SRC = { pcgw: 'ds4.src.pcgw', steam: 'ds4.src.steam', files: 'ds4.src.files' };
const SUG = { off: 'ds4.sug.off', on: 'ds4.sug.on', offMaybe: 'ds4.sug.offMaybe', onMaybe: 'ds4.sug.onMaybe', depends: 'ds4.sug.depends', unknown: 'ds4.sug.unknown', none: 'ds4.sug.none' };
const normTitle = (s) => String(s || '').toLowerCase().replace(/[^a-z0-9]/g, '');

function adviceFor(g) {
  const d = S.ds4;
  return PadAdvice.advise(g, d.facts[g.id] || {}, d.pads, { wraps: d.wraps, hides: d.hides }, d.feedback[g.id]);
}
function sugText(a) {
  if ((a.mode === 'on' || a.mode === 'off') && !a.sure) return t(SUG[a.mode + 'Maybe']);
  return t(SUG[a.mode] || SUG.unknown);
}
// "DualShock 4 (Bluetooth): the game reads it only with a cable · ... · Source: PCGamingWiki"
function whyText(g, a) {
  const parts = [];
  if (a.why && WHY[a.why]) parts.push(t(WHY[a.why]));
  if (a.mode !== 'none' && !(a.srcs || []).includes('you') && !S.ds4.hides) {
    for (const x of a.per) parts.push(t('ds4.padLine', { pad: t(PAD_NAME[x.pad.model]), link: t(PAD_LINK[x.pad.link]), why: t(WHY[x.why] || WHY.unknown) }));
  }
  const f = S.ds4.facts[g.id] || {};
  const srcs = (a.srcs || []).filter((s) => SRC[s]).map((s) => (s === 'pcgw' && f.pcgw && normTitle(f.pcgw.page) !== normTitle(g.name) ? t('ds4.src.pcgwPage', { page: f.pcgw.page }) : t(SRC[s])));
  if (srcs.length) parts.push(t('ds4.sources', { list: srcs.join(', ') }));
  if (a.tip === 'steamInput') parts.push(t('ds4.tip.steamInput'));
  return parts.join(' · ');
}
async function renderDs4(st) {
  const box = $('#ds4-block');
  if (!st.ds4windows) { box.hidden = true; return; }
  const d = await ensureDs4(true);
  box.hidden = !d.found;
  if (!d.found) return;
  $('#ds4-status').textContent = d.running ? t('ds4.running') : t('ds4.notRunning');
  renderPads(d);
  renderDs4Check(d);
  renderDs4Table(d);
}
function renderPads(d) {
  $('#ds4-pads').replaceChildren(...d.pads.map((p) => {
    const sel = h('select', { class: 'select', 'aria-label': t(PAD_NAME[p.model]) }, ...['bt', 'usb', 'none'].map((l) => h('option', { value: l }, t(PAD_LINK[l]))));
    sel.value = p.link || 'none';
    sel.addEventListener('change', () => setPad(p.model, sel.value));
    return h('label', { class: 'pad' }, h('span', { class: 'pad-name' }, t(PAD_NAME[p.model])), sel, h('em', {}, PAD_HOW[p.how] ? t(PAD_HOW[p.how]) : ''));
  }));
  const tips = [];
  if (d.hides) tips.push(t('ds4.tip.hides'));
  else if (d.wraps && d.wraps.dualsense !== false && d.pads.some((p) => p.model === 'dualsense' && p.link !== 'none')) tips.push(t('ds4.tip.dualsense'));
  if (!d.pads.some((p) => p.link && p.link !== 'none')) tips.push(t('ds4.tip.noPads'));
  $('#ds4-tip').textContent = tips.join(' ');
  $('#ds4-tip').hidden = !tips.length;
}
async function setPad(model, link) {
  try {
    await api.post('/api/settings', { pads: { [model]: link } });
    const p = S.ds4.pads.find((x) => x.model === model);
    if (p) { p.link = link; p.how = 'set'; }
    renderPads(S.ds4); renderDs4Table(S.ds4);
  } catch (e) { toast(errText(e), 'error'); }
}
function renderDs4Check(d) {
  const btn = $('#btn-ds4-check');
  btn.disabled = !!d.checking;
  btn.textContent = d.checkedAt ? t('ds4.checkAgain') : t('ds4.check');
  let s = d.checkedAt ? t('ds4.checked', { date: fmtStamp(d.checkedAt) }) : t('ds4.neverChecked');
  if (d.checking) s = d.progress && d.progress.total ? t('ds4.checking', { done: fmtNum(d.progress.done), total: fmtNum(d.progress.total) }) : t('ds4.checkingStart');
  $('#ds4-check-status').textContent = s;
  if (d.checking) pollDs4Check();
}
let ds4Poll = null;
function pollDs4Check() {
  if (ds4Poll) return;
  ds4Poll = setInterval(async () => {
    const d = await ensureDs4(true);
    if (!d.checking) {
      clearInterval(ds4Poll); ds4Poll = null;
      if (!$('#ds4-block').hidden) { renderPads(d); renderDs4Table(d); }
      toast(t('ds4.checkDone'));
    }
    if (!$('#ds4-block').hidden) renderDs4Check(d);
  }, 2500);
}
function renderDs4Table(d) {
  const games = library().slice().sort((a, b) => (!!d.games[b.id] - !!d.games[a.id]) || byName(a, b));
  $('#ds4-table').replaceChildren(...games.map((g) => {
    const a = adviceFor(g);
    const sel = h('select', { class: 'select', 'data-id': g.id, 'aria-label': t('ds4.forGame', { name: g.name }) });
    ds4Options(sel, d.games[g.id]);
    const chip = h('span', { class: 'ds4-sug', 'data-mode': a.mode }, sugText(a));
    const mark = () => chip.classList.toggle('differs', (a.mode === 'on' || a.mode === 'off') && ruleOf(sel.value) !== a.mode);
    sel.addEventListener('change', mark); mark();
    const why = h('span', { class: 'ds4-why' }, whyText(g, a));
    const fb = d.feedback[g.id];
    if (fb && fb.answer && fb.answer !== 'skip') why.append(' ', h('button', { class: 'link', type: 'button', onclick: (e) => { e.preventDefault(); forgetAnswer(g); } }, t('ds4.forget')));
    else if (a.mode !== 'none') why.append(' ', h('button', { class: 'link', type: 'button', onclick: (e) => { e.preventDefault(); openPadAsk(g, true); } }, t('ds4.tell')));
    return h('label', { class: 'ds4-row' }, h('span', { class: 'ds4-main' }, h('span', { class: 'ds4-name' }, g.name, ' ', h('em', {}, srcName(g.source, true))), why), chip, sel);
  }));
}
async function forgetAnswer(g) {
  try { const r = await api.post('/api/ds4windows/feedback', { id: g.id, answer: 'clear' }); S.ds4.feedback = r.feedback || {}; renderDs4Table(S.ds4); }
  catch (e) { toast(errText(e), 'error'); }
}
function ds4Toast(r, count) {
  if (!r) { toast(t('ds4.failed'), 'error'); return; }
  const what = count != null ? tn('ds4.appliedN', count) : t('ds4.applied');
  toast(`${what} ${r.restarted ? t('ds4.restarted') : t('ds4.notRunningNote')}`);
}

// after playing a game started from the hub: one question, once per game, when the suggestion is unsure
function askAfterPlay() {
  const a = S.askAfter;
  if (!a) return;
  const p = S.playtime[a.id];
  if (!p || !p.last || new Date(p.last).getTime() < a.at - 60000) return;   // no finished session yet
  S.askAfter = null;
  maybeAskPad(a.id);
}
async function maybeAskPad(id) {
  const g = library().find((x) => x.id === id);
  if (!g || document.querySelector('dialog[open]')) return;
  const d = await ensureDs4(true);
  if (!d.found || (d.feedback[id] && d.feedback[id].answer)) return;
  const a = adviceFor(g);
  if (a.mode === 'none' || a.sure) return;
  openPadAsk(g, false);
}
// tell: from "Tell Game Hub" in Settings, any time (the answer says whether DS4Windows was on or off)
function openPadAsk(g, tell) {
  S.askId = g.id; S.askOffer = null;
  $('#pad-ask-title').textContent = t(tell ? 'ask.tellTitle' : 'ask.title', { name: g.name });
  $('#pad-ask-q').hidden = false; $('#pad-ask-btns').hidden = tell; $('#pad-tell-btns').hidden = !tell; $('#pad-ask-skip').hidden = tell;
  $('#pad-ask-offer').hidden = true; $('#pad-ask-apply').hidden = true;
  $('#pad-ask').showModal();
}
async function answerPad(answer, rule) {
  const g = library().find((x) => x.id === S.askId);
  if (!g) { $('#pad-ask').close(); return; }
  try { const r = await api.post('/api/ds4windows/feedback', { id: g.id, answer, rule }); S.ds4.feedback = r.feedback || {}; }
  catch (e) { $('#pad-ask').close(); toast(errText(e), 'error'); return; }
  if (answer === 'skip') { $('#pad-ask').close(); return; }
  const a = adviceFor(g);
  const cur = ruleOf(S.ds4.games[g.id]);
  if ((a.mode === 'on' || a.mode === 'off') && a.mode !== cur) {
    S.askOffer = a.mode;
    $('#pad-ask-q').hidden = true; $('#pad-ask-skip').hidden = true;
    $('#pad-ask-offer').textContent = t(a.mode === 'off' ? 'ask.offerOff' : 'ask.offerOn', { name: g.name });
    $('#pad-ask-offer').hidden = false; $('#pad-ask-apply').hidden = false;
    $('#pad-ask-apply').focus();
    return;
  }
  $('#pad-ask').close();
  toast(answer === 'none' && !rule && cur === 'on' ? t('ask.checkSettings', { name: g.name }) : t('ask.thanks', { name: g.name }));
  if (S.settings && !$('#ds4-block').hidden) renderDs4Table(S.ds4);
}

function renderTabs() {
  const r = S.q ? {} : S.route;
  const tabs = [['#/', t('nav.home'), r.view === 'home'], ...launcherOrder().map((k) => [`#/l/${k}`, srcName(k), r.source === k])];
  $('#tabs').replaceChildren(...tabs.map(([href, label, on]) => h('a', { href, 'aria-current': on ? 'page' : null }, label)));
  if (r.view === 'settings') $('#nav-settings').setAttribute('aria-current', 'page'); else $('#nav-settings').removeAttribute('aria-current');
}

const currentView = () => (S.locked ? 'locked' : S.setup ? 'setup' : S.q ? 'grid' : S.route.view);
function showView(view) {
  for (const v of ['home', 'grid', 'settings', 'setup']) $('#view-' + v).hidden = v !== view;
  $('#nav').classList.toggle('setup-mode', view === 'setup');
}
function render() {
  if (!S.catalog || S.setup || S.locked) return;
  const view = currentView();
  showView(view);
  renderTabs();
  if (view === 'home') renderHome();
  else if (view === 'grid') renderGridView();
  else renderSettings();
  const ex = (S.catalog.excludedDrives || []).filter(Boolean).join(', ');
  $('#footer').textContent = [tn('n.games', library().length), t('footer.scanned', { date: fmtStamp(S.catalog.generatedAt) }), ex && t('footer.neverRead', { drives: ex })].filter(Boolean).join(' · ');
  updateNav();
}
function updateNav() { $('#nav').classList.toggle('solid', window.scrollY > 30 || $('#view-home').hidden); }

// ------------------------------------------------------------------ first-run setup
const SU = { step: 1, drives: [], ex: new Set(), folders: [], extra: [], launchers: [], accounts: [] };
async function showSetup() {
  S.setup = true;
  showView('setup');
  $('#footer').textContent = '';
  updateNav();
  fillLangSelect($('#setup-language'), S.langPref);
  setupStep(1);
  $('#setup-drives').replaceChildren(h('li', { class: 'empty-li' }, t('setup.looking')));
  try {
    const [d, st] = await Promise.all([api.get('/api/setup/drives'), api.get('/api/settings').catch(() => ({}))]);
    SU.drives = (d.drives || []).filter(Boolean);
    // pre-ticked: drives already excluded, and every USB or removable drive (a USB SSD often calls itself fixed)
    SU.ex = new Set(SU.drives.filter((x) => !x.system && (x.excluded || x.usb || x.type === 'removable')).map((x) => x.letter));
    SU.accounts = (st.otherAccounts || []).filter(Boolean);
    drivePicker($('#setup-drives'), SU.drives, SU.ex);
    $('#setup-lock-row').hidden = !SU.accounts.length;
  } catch (e) { toast(errText(e), 'error'); }
}
function setupStep(n) {
  SU.step = n;
  for (const i of [1, 2, 3]) $('#setup-' + i).hidden = i !== n;
  for (const li of document.querySelectorAll('#setup-steps li')) {
    const i = Number(li.dataset.step);
    li.className = i === n ? 'on' : i < n ? 'done' : '';
    li.toggleAttribute('aria-current', i === n);
  }
  window.scrollTo(0, 0);
}
const setupCheck = async (paths) => ((await api.post('/api/setup/check', { paths, exclude: [...SU.ex] })).results || []).filter(Boolean);
async function enterFolders() {
  setupStep(2);
  $('#setup-folders').replaceChildren(h('li', { class: 'empty-li' }, t('setup.looking')));
  $('#setup-launchers').replaceChildren();
  try {
    const r = await api.post('/api/setup/folders', { exclude: [...SU.ex] });
    SU.launchers = (r.launchers || []).filter(Boolean);
    const prev = new Map(SU.folders.map((f) => [f.path.toLowerCase(), f.on]));
    const suggested = (r.suggestions || []).filter(Boolean).map((s) => s.path);
    const res = await setupCheck([...suggested, ...SU.extra]);
    const mine = new Set(SU.extra.map((p) => p.toLowerCase()));
    // suggestions that turn out missing or excluded are left out; folders you added always show
    SU.folders = res.filter((x) => mine.has(x.path.toLowerCase()) || x.status === 'ok' || x.status === 'launcher')
      .map((x) => ({ ...x, on: prev.has(x.path.toLowerCase()) ? prev.get(x.path.toLowerCase()) : true }));
  } catch (e) { toast(errText(e), 'error'); }
  renderSetupFolders();
}
function renderSetupFolders() {
  $('#setup-launchers').replaceChildren(...(SU.launchers.length
    ? SU.launchers.map((l) => h('li', {}, h('b', {}, l.launcher), h('span', { title: l.path }, l.path)))
    : [h('li', { class: 'empty-li' }, t('setup.noLaunchers'))]));
  $('#setup-folders').replaceChildren(...(SU.folders.length ? SU.folders.map((f) => folderCheckRow(f)) : [h('li', { class: 'empty-li' }, t('setup.noFolders'))]));
}
async function addSetupFolders(paths) {
  const known = new Set(SU.folders.map((f) => f.path.toLowerCase()));
  const fresh = paths.filter((p) => !known.has(p.toLowerCase()));
  if (!fresh.length) { toast(t('check.already')); return; }
  SU.extra.push(...fresh);
  const prev = new Map(SU.folders.map((f) => [f.path.toLowerCase(), f.on]));
  try {
    const res = await setupCheck([...SU.folders.map((f) => f.path), ...fresh]);
    SU.folders = res.map((x) => ({ ...x, on: prev.has(x.path.toLowerCase()) ? prev.get(x.path.toLowerCase()) : true }));
    const last = res[res.length - 1];
    if (fresh.length === 1 && last && last.status !== 'ok') toast(statusText(last), 'error');
  } catch (e) { toast(errText(e), 'error'); }
  renderSetupFolders();
}
async function finishSetup(btn) {
  const body = {
    exclude: [...SU.ex],
    gameRoots: SU.folders.filter((f) => f.status === 'ok' && f.on).map((f) => f.path),
    startup: $('#setup-startup').checked, minimizeOnLaunch: $('#setup-minimize').checked, restoreAfterGame: $('#setup-restore').checked,
    lockToAccount: !$('#setup-lock-row').hidden && $('#setup-lock').checked, language: $('#setup-language').value,
  };
  btn.disabled = true;
  try {
    await api.post('/api/setup/finish', body);
    S.route = { view: 'home' };                    // the setup page stays until the scan has a library
    if (location.hash && location.hash !== '#/') history.replaceState(null, '', '#/');
    await waitForJob(t('setup.scanning'));
    if (S.catalog) toast(tn('toast.found', library().length));
  } catch (e) { toast(errText(e), 'error'); }
  finally { btn.disabled = false; }
}

// ------------------------------------------------------------------ find game folders with an AI
// The prompt names the drives to stay away from and the launcher folders already covered. The answer
// is pasted back, every path in it is checked by the server, and only folders that pass can be added.
const AI = { ctx: null, results: [] };
function buildPrompt(c) {
  const ex = new Set(c.exclude);
  const allowed = c.drives.filter((d) => d.type === 'fixed' && !ex.has(d.letter)).map((d) => d.letter);
  const lines = [t('ai.p.intro'), ''];
  if (allowed.length) lines.push('- ' + t('ai.p.drives', { list: allowed.join(', ') }));
  if (ex.size) lines.push('- ' + t('ai.p.never', { list: [...ex].sort().join(', ') }));
  lines.push('- ' + t('ai.p.shape'), '- ' + t('ai.p.readOnly'));
  if (c.launchers.length) { lines.push('- ' + t('ai.p.skip')); for (const l of c.launchers) lines.push(`    ${l.path}  (${l.launcher})`); }
  if (c.current.length) { lines.push('- ' + t('ai.p.have')); for (const p of c.current) lines.push('    ' + p); }
  lines.push('- ' + t('ai.p.chat'), '', t('ai.p.answer'), '```', 'X:\\Games', 'X:\\Other games', '```');
  return lines.join('\n');
}
// pulls full Windows folder paths out of an answer (a code block when there is one, else every line)
function parsePaths(text) {
  const blocks = [...text.matchAll(/```[^\n]*\n([\s\S]*?)```/g)].map((m) => m[1]);
  const out = [];
  for (const line of (blocks.length ? blocks.join('\n') : text).split(/\r?\n/)) {
    for (const part of line.replace(/\//g, '\\').split(/(?=\b[A-Za-z]:\\)/)) {        // ":" never appears inside a folder name
      if (!/^[A-Za-z]:\\/.test(part)) continue;
      const p = part.replace(/\s+(#|--|\u2014|\u2013|\/\/).*$/, '').replace(/[`"'*]+/g, '').replace(/[\s,;.]+$/, '');
      if (p.length >= 3 && !out.some((x) => x.toLowerCase() === p.toLowerCase())) out.push(p);
    }
  }
  return out.slice(0, 100);
}
function openAi(ctx) {
  AI.ctx = ctx;
  AI.results = [];
  $('#ai-form').reset();
  $('#ai-prompt').value = buildPrompt(ctx);
  $('#ai-results').replaceChildren();
  $('#ai-add').disabled = true;
  $('#ai').showModal();
}
async function openAiFromSettings() {
  const st = S.settings;
  if (!st) return;
  let launchers = [];
  try { launchers = ((await api.post('/api/setup/folders', { exclude: st.excluded })).launchers || []).filter(Boolean); } catch (e) { /* prompt without them */ }
  openAi({ drives: (st.drives || []).filter(Boolean), exclude: st.excluded, launchers, current: st.gameRoots, onAdd: (paths) => saveRoots([...st.gameRoots, ...paths]) });
}
async function copyPrompt() {
  const ta = $('#ai-prompt');
  try { await navigator.clipboard.writeText(ta.value); }
  catch (e) { ta.select(); document.execCommand('copy'); }
  toast(t('ai.copied'));
}
async function checkAi(btn) {
  const paths = parsePaths($('#ai-answer').value);
  if (!paths.length) { toast(t('ai.nonePasted'), 'error'); return; }
  const c = AI.ctx;
  btn.disabled = true;
  try {
    // the folders you already have go first, so the check can say "already in your list" / "inside another folder"
    const r = await api.post('/api/setup/check', { paths: [...c.current, ...paths], exclude: c.exclude });
    AI.results = (r.results || []).slice(c.current.length).map((x) => ({ ...x, status: x.status === 'duplicate' ? 'already' : x.status, on: true }));
    const upd = () => { $('#ai-add').disabled = !AI.results.some((x) => x.status === 'ok' && x.on); };
    $('#ai-results').replaceChildren(...AI.results.map((x) => folderCheckRow(x, upd)));
    upd();
  } catch (e) { toast(errText(e), 'error'); }
  finally { btn.disabled = false; }
}
function addAi() {
  const picked = AI.results.filter((x) => x.status === 'ok' && x.on).map((x) => x.path);
  if (!picked.length) return;
  $('#ai').close();
  AI.ctx.onAdd(picked);
}

// ------------------------------------------------------------------ actions
async function launch(g, el) {
  if (el) { el.classList.add('launching'); setTimeout(() => el.classList.remove('launching'), 4500); }
  try {
    const r = await api.post('/api/launch', { id: g.id });
    S.launches[g.id] = r.launchedAt;
    S.askAfter = { id: g.id, at: Date.now() };
    toast(t('toast.launching', { name: g.name }));
    setTimeout(() => { if (!$('#view-home').hidden) renderHome(); }, 1800);
  } catch (e) {
    if (el) el.classList.remove('launching');
    toast(t('toast.launchFailed', { name: g.name, msg: errText(e) }), 'error');
  }
}
async function toggleFav(g) {
  try {
    const st = await api.post('/api/favorite', { id: g.id, value: !S.favs.has(g.id) });
    S.favs = new Set(st.favorites || []);
    toast(S.favs.has(g.id) ? t('toast.favAdded', { name: g.name }) : t('toast.favRemoved', { name: g.name }));
    render();
  } catch (e) { toast(t('toast.favFailed', { msg: errText(e) }), 'error'); }
}
async function openFolder(body, label) {
  try { await api.post('/api/open-folder', body); toast(t('toast.folderOpened', { name: label })); } catch (e) { toast(t('toast.folderFailed', { msg: errText(e) }), 'error'); }
}
async function pick(kind, initial) {
  toast(kind === 'folder' ? t('pick.folder') : t('pick.exe'), '', true);
  try { const r = await api.post('/api/pick', { kind, initial }); toast(r.path ? t('pick.selected') : t('pick.none')); return r.path || null; }
  catch (e) { toast(t('pick.failed', { msg: errText(e) }), 'error'); return null; }
}
async function rescan(btn) {
  if (btn) btn.disabled = true;
  try { await api.post('/api/rescan'); await waitForJob(t('toast.scanning')); toast(t('toast.libraryUpdated', { games: tn('n.games', library().length) })); }
  catch (e) { toast(t('toast.rescanFailed', { msg: errText(e) }), 'error'); }
  finally { if (btn) btn.disabled = false; }
}
async function saveRoots(list) {
  try { await api.post('/api/settings', { gameRoots: list }); await waitForJob(t('toast.foldersSaved')); toast(t('toast.foldersUpdated')); }
  catch (e) { toast(errText(e), 'error'); }
}
async function unhide(x) {
  try { await api.post('/api/game/unhide', { id: x.id }); await waitForJob(t('toast.unhiding', { name: x.name })); toast(t('toast.unhidden', { name: x.name })); }
  catch (e) { toast(errText(e), 'error'); }
}
async function restoreBackup(x) {
  if (!confirm(t('backups.confirmRestore', { date: fmtStamp(x.created) }))) return;
  try {
    await api.post('/api/backups/restore', { name: x.name });
    S.bust = Date.now(); S.ds4 = null;
    await load();
    toast(t('backups.restored', { date: fmtStamp(x.created) }));
  } catch (e) { toast(errText(e), 'error'); }
}

// ------------------------------------------------------------------ edit dialog (pen icon)
const editing = () => findGame(S.editId);
const via = (g) => VIA[g.source] || t('edit.itsLauncher');
function openEdit(id) {
  const g = findGame(id);
  if (!g) return;
  S.editId = id;
  $('#edit-title').textContent = t('edit.title', { name: g.name });
  $('#edit-name').value = g.name;
  $('#edit-exe').value = g.exe || '';
  $('#edit-args').value = (g.launch && g.launch.args) || '';
  $('#edit-dir').textContent = g.installDir;
  $('#edit-warning').hidden = !g.warning;
  $('#edit-warning').textContent = g.warning || '';
  $('#edit-hide').textContent = g.manual ? t('edit.remove') : t('edit.hide');
  $('#steam-pick').hidden = true;
  $('#edit-ds4-field').hidden = true;
  setLaunchHint(g, false);
  refreshEditArt();
  $('#edit').showModal();
  ensureDs4().then((d) => {
    if (!d.found || S.editId !== id) return;
    ds4Options($('#edit-ds4'), d.games[id]);
    const a = adviceFor(g);
    $('#edit-ds4-why').textContent = a.mode === 'none' ? '' : sugText(a) + ' · ' + whyText(g, a);
    $('#edit-ds4-field').hidden = false;
  });
}
function setLaunchHint(g, exeChanged) {
  const hint = $('#edit-launch-hint');
  const viaLauncher = g.launch.type === 'uri' && !g.customExe && !exeChanged;
  $('#edit-args').disabled = viaLauncher;
  $('#edit-args').placeholder = viaLauncher ? t('edit.argsNotUsed', { launcher: via(g) }) : '-windowed';
  if (exeChanged) hint.replaceChildren(t('edit.hintDirect'));
  else if (viaLauncher) hint.replaceChildren(t('edit.hintVia', { launcher: via(g) }));
  else if (g.customExe) hint.replaceChildren(t('edit.hintCustom'), ' ', h('button', { class: 'link', type: 'button', onclick: resetExe }, g.defaultUri ? t('edit.backToLauncher', { launcher: via(g) }) : t('edit.backToDetected')));
  else hint.replaceChildren(t('edit.hintFile'));
}
function refreshEditArt() {
  const g = editing();
  if (!g) return;
  $('#edit-drop').replaceChildren(posterArt(g), h('div', { class: 'drop-hint' }, t('edit.dropImage')));
  $('#edit-reset-cover').hidden = !hasCustom(g, 'cover');
  $('#edit-reset-hero').hidden = !hasCustom(g, 'hero');
}
async function afterArtChange(msg) { S.bust = Date.now(); await load(); refreshEditArt(); toast(msg); }

async function uploadArt(file, kind) {
  const g = editing();
  if (!g || !file) return;
  if (!/^image\/(png|jpeg|webp)$/.test(file.type)) { toast(t('err.imageType'), 'error'); return; }
  if (file.size > 25 * 1024 * 1024) { toast(t('err.imageSize'), 'error'); return; }
  try {
    await api.post(`/api/cover/upload?id=${encodeURIComponent(g.id)}&kind=${kind}`, null, file);
    await afterArtChange(kind === 'cover' ? t('toast.coverUpdated') : t('toast.heroUpdated'));
  } catch (e) { toast(t('toast.uploadFailed', { msg: errText(e) }), 'error'); }
}
let uploadKind = 'cover';
function chooseImage(kind) { uploadKind = kind; $('#file').value = ''; $('#file').click(); }

async function steamSearch() {
  const q = $('#steam-q').value.trim();
  const box = $('#steam-results');
  if (q.length < 2) return;
  box.replaceChildren(h('p', { class: 'none' }, t('steam.searching')));
  try {
    const r = await api.post('/api/steam/search', { q });
    box.replaceChildren(...(r.items.length ? r.items.map((it) => h('button', { type: 'button', title: t('steam.useTip', { name: it.name, appid: it.appid }), onclick: () => useSteamArt(it) },
      h('img', { src: it.thumb, alt: '', loading: 'lazy' }), h('span', {}, it.name))) : [h('p', { class: 'none' }, t('steam.noMatch'))]));
  } catch (e) { box.replaceChildren(h('p', { class: 'none' }, t('steam.failed', { msg: errText(e) }))); }
}
async function useSteamArt(it) {
  const g = editing();
  toast(t('steam.downloading', { name: it.name }), '', true);
  try { await api.post('/api/cover/steam', { id: g.id, appid: it.appid }); await afterArtChange(t('steam.done', { name: it.name })); $('#steam-pick').hidden = true; }
  catch (e) { toast(errText(e), 'error'); }
}
async function resetExe() {
  const g = editing();
  try { await api.post('/api/game/save', { id: g.id, resetExe: true }); $('#edit').close(); await waitForJob(t('toast.restoringLaunch')); toast(t('toast.defaultLaunch', { name: g.name })); }
  catch (e) { toast(errText(e), 'error'); }
}
async function saveEdit() {
  const g = editing();
  const body = { id: g.id, name: $('#edit-name').value.trim() };
  const exe = $('#edit-exe').value.trim();
  if (exe && exe !== (g.exe || '')) body.exe = exe;
  if (!$('#edit-args').disabled) body.args = $('#edit-args').value.trim();
  const ds4Was = S.ds4 && S.ds4.found ? S.ds4.games[g.id] || 'on' : null;
  if (ds4Was && !$('#edit-ds4-field').hidden && $('#edit-ds4').value !== ds4Was) body.ds4 = $('#edit-ds4').value;
  if (!body.name) { toast(t('err.nameEmpty'), 'error'); return; }
  const btn = $('#edit-save');
  btn.disabled = true;
  try {
    const r = await api.post('/api/game/save', body);
    $('#edit').close();
    if (body.ds4) { if (body.ds4 === 'on') delete S.ds4.games[g.id]; else S.ds4.games[g.id] = body.ds4; }
    if (r.rescanning) await waitForJob(t('toast.savedRefreshing')); else await load();
    if (body.ds4) ds4Toast(r.ds4); else toast(t('toast.saved', { name: body.name }));
  } catch (e) { toast(errText(e), 'error'); }
  finally { btn.disabled = false; }
}
async function hideGame() {
  const g = editing();
  if (!confirm(g.manual ? t('edit.confirmRemove', { name: g.name }) : t('edit.confirmHide', { name: g.name }))) return;
  try { await api.post('/api/game/save', { id: g.id, hidden: true }); $('#edit').close(); await load(); toast(g.manual ? t('toast.removed', { name: g.name }) : t('toast.hid', { name: g.name })); }
  catch (e) { toast(errText(e), 'error'); }
}

// ------------------------------------------------------------------ add dialog
function openAdd() { $('#add-form').reset(); $('#add').showModal(); }
function guessName(path) {
  const base = path.split('\\').pop().replace(/\.exe$/i, '').replace(/[-_]+(win64|shipping|x64|dx1[12])/gi, '');
  return base.replace(/([a-z])([A-Z])/g, '$1 $2').replace(/[_.]+/g, ' ').trim();
}
async function saveAdd() {
  const exe = $('#add-exe').value.trim(), name = $('#add-name').value.trim() || guessName(exe);
  if (!exe) { toast(t('err.exeChoose'), 'error'); return; }
  const btn = $('#add-save');
  btn.disabled = true;
  try {
    await api.post('/api/game/add', { name, exe, args: $('#add-args').value.trim() });
    $('#add').close();
    await waitForJob(t('toast.adding', { name }));
    toast(t('toast.added', { name }));
  } catch (e) { toast(errText(e), 'error'); }
  finally { btn.disabled = false; }
}

// ------------------------------------------------------------------ wiring
const q = $('#q');
q.addEventListener('input', () => { S.q = q.value; render(); window.scrollTo(0, 0); });
q.addEventListener('keydown', (e) => {
  if (e.key === 'Enter') { const first = $('#grid .poster'); if (first) first.click(); }
  if (e.key === 'Escape') { q.value = ''; S.q = ''; q.blur(); render(); }
});
document.addEventListener('keydown', (e) => {
  if (document.querySelector('dialog[open]') || S.setup) return;
  if ((e.key === '/' || (e.key.toLowerCase() === 'k' && (e.ctrlKey || e.metaKey))) && document.activeElement !== q) { e.preventDefault(); q.focus(); q.select(); }
});
window.addEventListener('scroll', updateNav, { passive: true });
window.addEventListener('hashchange', () => {
  S.route = parseRoute();
  if (S.q) { S.q = ''; q.value = ''; }
  render();
  window.scrollTo(0, 0);
});
function parseRoute() {
  const [a, b] = location.hash.replace(/^#\/?/, '').split('/');
  if (a === 'settings') return { view: 'settings' };
  if (a === 'l' && SOURCES[b] != null) return { view: 'grid', source: b };
  if (a === 'd' && /^[a-z]$/i.test(b || '')) return { view: 'grid', drive: b.toUpperCase() + ':' };
  if (a === 'all') return { view: 'grid' };
  return { view: 'home' };
}
$('#grid-sort').addEventListener('change', (e) => { S.sort = SORTS[e.target.value] ? e.target.value : 'name'; store.set('sort', S.sort); render(); });

$('#edit-save').addEventListener('click', saveEdit);
$('#edit-hide').addEventListener('click', hideGame);
$('#edit-browse').addEventListener('click', async () => {
  const g = editing();
  const p = await pick('exe', $('#edit-exe').value || g.installDir);
  if (p) { $('#edit-exe').value = p; setLaunchHint(g, p !== (g.exe || '')); }
});
$('#edit-exe').addEventListener('input', () => { const g = editing(); setLaunchHint(g, $('#edit-exe').value.trim() !== (g.exe || '')); });
$('#edit-upload').addEventListener('click', () => chooseImage('cover'));
$('#edit-upload-hero').addEventListener('click', () => chooseImage('hero'));
$('#file').addEventListener('change', (e) => uploadArt(e.target.files[0], uploadKind));
$('#edit-reset-cover').addEventListener('click', async () => { await api.post('/api/cover/reset', { id: S.editId, kind: 'cover' }); await afterArtChange(t('toast.coverRemoved')); });
$('#edit-reset-hero').addEventListener('click', async () => { await api.post('/api/cover/reset', { id: S.editId, kind: 'hero' }); await afterArtChange(t('toast.heroRemoved')); });
$('#edit-steam').addEventListener('click', () => {
  const p = $('#steam-pick');
  p.hidden = !p.hidden;
  if (!p.hidden) { $('#steam-q').value = editing().name; steamSearch(); $('#steam-q').focus(); }
});
$('#steam-go').addEventListener('click', steamSearch);
$('#steam-q').addEventListener('keydown', (e) => { if (e.key === 'Enter') { e.preventDefault(); steamSearch(); } });
const drop = $('#edit-drop');
drop.addEventListener('dragover', (e) => { e.preventDefault(); drop.classList.add('over'); });
drop.addEventListener('dragleave', () => drop.classList.remove('over'));
drop.addEventListener('drop', (e) => {
  e.preventDefault(); drop.classList.remove('over');
  const f = e.dataTransfer.files && e.dataTransfer.files[0];
  if (f) uploadArt(f, 'cover'); else toast(t('edit.dropFile'), 'error');
});

$('#add-browse').addEventListener('click', async () => {
  const p = await pick('exe', $('#add-exe').value);
  if (p) { $('#add-exe').value = p; if (!$('#add-name').value) $('#add-name').value = guessName(p); }
});
$('#add-save').addEventListener('click', saveAdd);

// setup page
$('#setup-next-1').addEventListener('click', enterFolders);
$('#setup-back-2').addEventListener('click', () => setupStep(1));
$('#setup-next-2').addEventListener('click', () => setupStep(3));
$('#setup-back-3').addEventListener('click', () => setupStep(2));
$('#setup-scan').addEventListener('click', (e) => finishSetup(e.currentTarget));
$('#setup-add-folder').addEventListener('click', async () => { const p = await pick('folder'); if (p) addSetupFolders([p]); });
$('#setup-ai').addEventListener('click', () => openAi({ drives: SU.drives, exclude: [...SU.ex], launchers: SU.launchers, current: SU.folders.map((f) => f.path), onAdd: addSetupFolders }));
$('#setup-language').addEventListener('change', async (e) => {
  // preview right away; saved when you click Scan
  if (await setLanguage(e.target.value)) {
    fillLangSelect(e.target, e.target.value);
    drivePicker($('#setup-drives'), SU.drives, SU.ex);
    renderSetupFolders();
  }
});

// AI dialog
$('#ai-copy').addEventListener('click', copyPrompt);
$('#ai-check').addEventListener('click', (e) => checkAi(e.currentTarget));
$('#ai-add').addEventListener('click', addAi);

// settings
$('#btn-rescan').addEventListener('click', (e) => rescan(e.currentTarget));
$('#btn-add').addEventListener('click', openAdd);
$('#btn-covers').addEventListener('click', async (e) => {
  const btn = e.currentTarget;
  btn.disabled = true;
  try { await api.post('/api/covers/fetch', { force: false }); await waitForJob(t('toast.coversLooking')); toast(t('toast.coversDone')); }
  catch (err) { toast(errText(err), 'error'); }
  finally { btn.disabled = false; }
});
$('#btn-add-folder').addEventListener('click', async () => {
  const p = await pick('folder');
  if (p && S.settings) saveRoots([...S.settings.gameRoots, p]);
});
$('#btn-ai-folders').addEventListener('click', openAiFromSettings);
$('#btn-save-drives').addEventListener('click', async (e) => {
  const btn = e.currentTarget;
  btn.disabled = true;
  try { await api.post('/api/settings', { excludeDriveLetters: [...S.setEx] }); await waitForJob(t('toast.drivesSaved')); toast(t('toast.drivesUpdated')); }
  catch (err) { toast(errText(err), 'error'); }
  finally { btn.disabled = false; }
});
for (const [el, key, on, off] of [
  ['#set-minimize', 'minimizeOnLaunch', 'toast.minimizeOn', 'toast.minimizeOff'],
  ['#set-restore', 'restoreAfterGame', 'toast.restoreOn', 'toast.restoreOff'],
  ['#set-track', 'trackOutsideLaunches', 'toast.trackOn', 'toast.trackOff'],
  ['#set-summon', 'controllerSummon', 'toast.summonOn', 'toast.summonOff'],
  ['#set-startup', 'startup', 'toast.startupOn', 'toast.startupOff'],
  ['#set-lock', 'lockToAccount', 'toast.lockOn', 'toast.lockOff'],
]) {
  $(el).addEventListener('change', async (e) => {
    try { const r = await api.post('/api/settings', { [key]: e.target.checked }); toast(t(r[key] ? on : off)); }
    catch (err) { toast(errText(err), 'error'); e.target.checked = !e.target.checked; }
  });
}
$('#set-language').addEventListener('change', async (e) => {
  try {
    await api.post('/api/settings', { language: e.target.value });
    await setLanguage(e.target.value);
    render();
    toast(t('toast.languageSaved', { name: langName(L.code) }));
  } catch (err) { toast(errText(err), 'error'); }
});
$('#btn-backup-now').addEventListener('click', async (e) => {
  const btn = e.currentTarget;
  btn.disabled = true;
  try { await api.post('/api/backups/create'); toast(t('backups.done')); renderBackups(); }
  catch (err) { toast(errText(err), 'error'); }
  finally { btn.disabled = false; }
});
$('#btn-backup-copy').addEventListener('click', async () => {
  const p = await pick('folder');
  if (!p) return;
  try { await api.post('/api/settings', { backupCopyTo: p }); toast(t('backups.copyToSet', { path: p })); renderBackups(); }
  catch (err) { toast(errText(err), 'error'); }
});
$('#btn-backup-copy-clear').addEventListener('click', async () => {
  try { await api.post('/api/settings', { backupCopyTo: '' }); toast(t('backups.copyToCleared')); renderBackups(); }
  catch (err) { toast(errText(err), 'error'); }
});
$('#btn-ds4-apply').addEventListener('click', async (e) => {
  const btn = e.currentTarget;
  const games = {};
  for (const sel of document.querySelectorAll('#ds4-table select')) games[sel.dataset.id] = sel.value;
  btn.disabled = true;
  try {
    const r = await api.post('/api/ds4windows', { games });
    await ensureDs4(true);
    ds4Toast(r, Object.values(games).filter((v) => v !== 'on').length);
    if (S.settings) renderDs4(S.settings);
  } catch (err) { toast(errText(err), 'error'); }
  finally { btn.disabled = false; }
});

$('#btn-ds4-check').addEventListener('click', async () => {
  try {
    await api.post('/api/ds4windows/check', { force: !!(S.ds4 && S.ds4.checkedAt) });
    Object.assign(S.ds4, { checking: true, progress: null });
    renderDs4Check(S.ds4);
  } catch (err) { toast(errText(err), 'error'); }
});
$('#btn-ds4-suggest').addEventListener('click', () => {
  let n = 0;
  for (const sel of document.querySelectorAll('#ds4-table select')) {
    const g = library().find((x) => x.id === sel.dataset.id);
    const a = g && adviceFor(g);
    if (a && (a.mode === 'on' || a.mode === 'off') && ruleOf(sel.value) !== a.mode) { sel.value = a.mode; sel.dispatchEvent(new Event('change')); n++; }
  }
  toast(n ? tn('ds4.usedSuggestions', n) : t('ds4.noSuggestions'));
});
for (const b of document.querySelectorAll('#pad-ask [data-answer]')) b.addEventListener('click', () => answerPad(b.dataset.answer, b.dataset.rule));
$('#pad-ask-apply').addEventListener('click', async () => {
  const g = library().find((x) => x.id === S.askId);
  const mode = S.askOffer;
  $('#pad-ask').close();
  if (!g || !mode) return;
  try {
    const r = await api.post('/api/game/save', { id: g.id, ds4: mode });
    if (mode === 'on') delete S.ds4.games[g.id]; else S.ds4.games[g.id] = mode;
    ds4Toast(r.ds4);
    if (S.settings && !$('#ds4-block').hidden) renderDs4Table(S.ds4);
  } catch (err) { toast(errText(err), 'error'); }
});

// back from a game: refresh play time and "last played" (and the library if a scan ran meanwhile)
window.addEventListener('focus', () => {
  if (S.locked || S.setup || !S.catalog || document.querySelector('dialog[open]')) return;
  api.get('/api/status').then(async (st) => {
    if (!st.scanning && (S.askAfter || st.generatedAt !== S.catalog.generatedAt || Date.now() - S.loadedAt > 30000)) await load();
    askAfterPlay();
  }).catch(() => {});
});

(async () => {
  await Promise.all([loadLangList(), loadAbout()]);
  S.route = parseRoute();
  try { await load(); }
  catch (e) {
    await setLanguage(S.langPref || 'auto');
    if (e.code === 'locked') return;
    document.body.append(h('p', { class: 'empty' }, t('err.load', { msg: errText(e) })));
  }
})();
