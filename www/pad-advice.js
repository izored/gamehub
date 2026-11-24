// What DS4Windows should do while a game runs: worked out from what is known about the game (data from
// check-controllers.ps1 and Steam's own settings), your controllers, DS4Windows' settings and your answers
// after playing. No page access here: app.js shows the result. Loaded before app.js.
//
// The idea: a game must see your controller once.
//  - the game reads your PlayStation controller by itself  -> DS4Windows off (otherwise it sees it twice)
//  - the game only understands Xbox controllers           -> DS4Windows on (it makes the controller look like one)
//  - Steam Input is on for a Steam game                    -> DS4Windows off (Steam already translates it)
// The answer depends on the controller and how it is connected: many games read a DualShock 4 only with a
// cable, but a DualSense over Bluetooth too.
(function () {
  'use strict';

  // does the game read this controller itself? { v: true | false | null, src, weak, cable }
  function native(f, pad) {
    const p = f && f.pcgw;
    if (p && p.ps === 'no') return { v: false, src: 'pcgw' };
    if (p && p.ps === 'yes') {
      const models = [].concat(p.models || []);
      if (models.length && !models.includes(pad.model)) return { v: false, src: 'pcgw' };
      if (pad.link === 'usb') return { v: p.usb !== false, src: 'pcgw', weak: p.usb == null };
      if (p.bt == null) return { v: true, src: 'pcgw', weak: true };          // supported, Bluetooth not stated
      const bt = [].concat(p.bt);
      return bt.includes(pad.model) ? { v: true, src: 'pcgw' } : { v: false, src: 'pcgw', cable: p.usb !== false, weak: !p.btListed };
    }
    const s = f && f.steam;
    if (s && s[pad.model]) return { v: true, src: 'steam', weak: true };
    if (f && f.files && [].concat(f.files).length) return { v: true, src: 'files', weak: true };
    if (s && (s.full || s.partial)) return { v: false, src: 'steam', weak: true }; // controller support listed, PlayStation not
    return { v: null };
  }

  // one controller: { use: 'on' | 'off' | null, why, src, weak, tip }
  function padVerdict(g, f, pad, ds4) {
    if (ds4.hides) return { use: 'on', why: 'hides' };
    const viaSteam = g.source === 'steam';
    const si = viaSteam ? (f && f.steamInput) || 'default' : null;
    if (si === 'on') return { use: 'off', why: 'steamInput' };
    const n = native(f, pad);
    if (n.v === true) return { use: 'off', why: 'native', src: n.src, weak: n.weak };
    if (n.v === false) {
      // with its default settings Steam translates PlayStation controllers for games that don't support them
      if (viaSteam && si === 'default' && !(f && f.steam && f.steam[pad.model])) return { use: 'off', why: 'steamTranslates', src: n.src, weak: true };
      return { use: 'on', why: n.cable ? 'cableOnly' : 'xboxOnly', src: n.src, weak: n.weak, tip: viaSteam ? 'steamInput' : null };
    }
    return { use: null, why: 'unknown' };
  }

  const ruleOf = (r) => (r === 'off' ? 'off' : 'on');                          // a profile still means "on"

  // g: game; f: facts; pads: [{ model, link }]; ds4: { wraps, hides }; fb: your answer after playing { answer, rule }
  // returns { mode: 'on' | 'off' | 'depends' | 'unknown' | 'none', sure, why, per: [...], srcs: [...], tip }
  function advise(g, f, pads, ds4, fb) {
    const wraps = (ds4 && ds4.wraps) || {};
    const have = (pads || []).filter((p) => p.link && p.link !== 'none');
    const used = have.filter((p) => wraps[p.model] !== false);
    if (!used.length) return { mode: 'none', sure: true, why: have.length ? 'notWrapped' : 'noPads', per: [], srcs: [] };
    const per = used.map((p) => Object.assign({ pad: p }, padVerdict(g, f, p, ds4 || {})));
    const srcs = [...new Set(per.map((x) => x.src).filter(Boolean))];
    const tip = per.map((x) => x.tip).find(Boolean) || null;
    // your answer after playing beats everything else
    if (fb && fb.answer === 'double') return { mode: 'off', sure: true, why: 'youDouble', per, srcs: ['you'], tip: null };
    if (fb && fb.answer === 'fine') return { mode: ruleOf(fb.rule), sure: true, why: ruleOf(fb.rule) === 'off' ? 'youFineOff' : 'youFineOn', per, srcs: ['you'], tip: null };
    if (fb && fb.answer === 'none' && ruleOf(fb.rule) === 'off') return { mode: 'on', sure: true, why: 'youNone', per, srcs: ['you'], tip: null };
    const known = per.filter((x) => x.use);
    const uses = [...new Set(known.map((x) => x.use))];
    let mode = 'unknown';
    if (uses.length === 1) mode = uses[0];
    else if (uses.length > 1) mode = 'depends';
    const sure = mode !== 'unknown' && mode !== 'depends' && known.length === per.length && !per.some((x) => x.weak);
    const why = fb && fb.answer === 'none' ? 'youNoneOn' : mode === 'depends' ? 'depends' : null;
    return { mode, sure, why, per, srcs, tip: why === 'youNoneOn' ? 'steamInput' : tip };
  }

  const api = { advise, native, padVerdict };
  if (typeof module !== 'undefined' && module.exports) module.exports = api;    // node tests
  else window.PadAdvice = api;
})();
