import AppKit
import Foundation
import WebKit

/// Finds the visible clickable element whose text best matches what was said, and clicks it.
enum Clicker {
    struct Outcome {
        let ok: Bool
        let message: String
    }

    static func click(spoken: String, dryRun: Bool = false, in webView: WKWebView, completion: @escaping (Outcome) -> Void) {
        let js = "(function(){\(core)\nreturn JSON.stringify(run(\(jsonLiteral(spoken)), \(dryRun)));})()"
        webView.evaluateJavaScript(js) { result, error in
            if let error {
                completion(Outcome(ok: false, message: "Page script failed: \(error.localizedDescription)"))
                return
            }
            guard let s = result as? String,
                  let data = s.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                completion(Outcome(ok: false, message: "No response from page"))
                return
            }
            if obj["ok"] as? Bool == true {
                let text = obj["clicked"] as? String ?? "?"
                let via = obj["via"] as? String ?? ""
                let score = obj["score"] as? Double ?? 0
                let label = "“\(text)” (\(via), \(Int(score * 100))%)"
                if dryRun {
                    completion(Outcome(ok: true, message: "Would click " + label))
                    return
                }
                if obj["inside"] as? Bool == true,
                   let rect = obj["rect"] as? [String: Any],
                   let x = rect["x"] as? Double, let y = rect["y"] as? Double,
                   let w = rect["w"] as? Double, let h = rect["h"] as? Double,
                   nativeClick(at: CGPoint(x: x + w / 2, y: y + h / 2), in: webView) {
                    completion(Outcome(ok: true, message: "Clicked " + label))
                    return
                }
                // Fall back to a scripted click when the element is not on screen.
                webView.evaluateJavaScript("(function(){\(core)\nreturn syntheticClick();})()") { _, _ in
                    completion(Outcome(ok: true, message: "Clicked (scripted) " + label))
                }
            } else {
                var msg = obj["reason"] as? String ?? "No match"
                if let top = obj["top"] as? [[String: Any]], !top.isEmpty {
                    let list = top.prefix(3).map { "“\($0["text"] as? String ?? "")” \(Int(($0["score"] as? Double ?? 0) * 100))%" }
                    msg += ". Closest: " + list.joined(separator: ", ")
                }
                completion(Outcome(ok: false, message: msg))
            }
        }
    }

    /// Sends a real mouse down/up through the window so the page receives trusted events.
    private static func nativeClick(at viewPoint: CGPoint, in webView: WKWebView) -> Bool {
        guard let window = webView.window else { return false }
        let p = webView.isFlipped ? viewPoint : CGPoint(x: viewPoint.x, y: webView.bounds.height - viewPoint.y)
        let winPoint = webView.convert(p, to: nil)
        let now = ProcessInfo.processInfo.systemUptime
        guard let move = NSEvent.mouseEvent(with: .mouseMoved, location: winPoint, modifierFlags: [], timestamp: now,
                                            windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 0, pressure: 0),
              let down = NSEvent.mouseEvent(with: .leftMouseDown, location: winPoint, modifierFlags: [], timestamp: now + 0.01,
                                            windowNumber: window.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1),
              let up = NSEvent.mouseEvent(with: .leftMouseUp, location: winPoint, modifierFlags: [], timestamp: now + 0.08,
                                          windowNumber: window.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 0)
        else { return false }
        window.sendEvent(move)
        window.sendEvent(down)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.07) { window.sendEvent(up) }
        return true
    }

    static func list(in webView: WKWebView, completion: @escaping ([String]) -> Void) {
        let js = "(function(){\(core)\nreturn JSON.stringify(listTexts());})()"
        webView.evaluateJavaScript(js) { result, _ in
            guard let s = result as? String,
                  let data = s.data(using: .utf8),
                  let arr = try? JSONSerialization.jsonObject(with: data) as? [String] else {
                completion([])
                return
            }
            completion(arr)
        }
    }

    private static func jsonLiteral(_ s: String) -> String {
        let data = (try? JSONSerialization.data(withJSONObject: [s])) ?? Data("[\"\"]".utf8)
        let arr = String(decoding: data, as: UTF8.self)
        return String(arr.dropFirst().dropLast())
    }

    // Raw string: backslashes below are passed to JavaScript untouched.
    static let core = #"""
    var THRESH = 0.55;
    var NUM = {zero:'0',one:'1',two:'2',three:'3',four:'4',five:'5',six:'6',seven:'7',eight:'8',nine:'9',ten:'10',
      eleven:'11',twelve:'12',thirteen:'13',fourteen:'14',fifteen:'15',sixteen:'16',seventeen:'17',eighteen:'18',nineteen:'19',
      twenty:'20',thirty:'30',forty:'40',fifty:'50',sixty:'60',seventy:'70',eighty:'80',ninety:'90',hundred:'100',thousand:'1000',
      percent:'percent', dollars:'dollar'};
    var ALIASES = {'next':'continue','go on':'continue','keep going':'continue','move on':'continue','proceed':'continue',
      'carry on':'continue','start':'get started','begin':'get started','lets go':'get started','lets start':'get started',
      'lets begin':'get started','done':'submit','check':'check answer','okay':'ok','close':'close','back':'back'};
    var LETTER = {a:'a',eh:'a',b:'b',be:'b',bee:'b',c:'c',see:'c',sea:'c',si:'c',d:'d',de:'d',dee:'d',e:'e',ee:'e',f:'f',ef:'f',eff:'f'};
    var ORD = {first:0,'1st':0,one:0,'1':0,second:1,'2nd':1,two:1,'2':1,to:1,too:1,third:2,'3rd':2,three:2,'3':2,
      fourth:3,'4th':3,four:3,'4':3,'for':3,fifth:4,'5th':4,five:4,'5':4,sixth:5,'6th':5,six:5,'6':5};
    var FILLER = ['the','option','answer','choice','number','select','click','choose','pick','letter','press','tap','on'];

    function norm(s) {
      s = String(s || '').toLowerCase().replace(/[’']/g, '');
      s = s.replace(/(\d),(\d)/g, '$1$2');
      s = s.replace(/\$/g, ' dollar ').replace(/%/g, ' percent ').replace(/&/g, ' and ');
      s = s.replace(/[^a-z0-9.]+/g, ' ');
      s = s.replace(/(\d)\.(\d)/g, '$1 point $2').replace(/\./g, ' ');
      return s.split(' ').filter(Boolean).map(function (w) { return NUM[w] || w; }).join(' ');
    }
    function cleanQuery(q) {
      q = norm(q);
      q = q.replace(/^(please )?(click|select|choose|press|tap|pick|hit|go to|open)( on)?( the)?( option| answer| choice| button)? /, '');
      q = q.replace(/ (button|option)$/, '');
      return q.trim();
    }
    function toks(s) { return s.split(' ').filter(Boolean); }
    function bigrams(s) { var b = []; for (var i = 0; i < s.length - 1; i++) b.push(s.slice(i, i + 2)); return b; }
    function dice(a, b) {
      if (a.length < 2 || b.length < 2) return a === b ? 1 : 0;
      var A = bigrams(a), Bl = bigrams(b), B = new Map();
      Bl.forEach(function (g) { B.set(g, (B.get(g) || 0) + 1); });
      var hit = 0;
      A.forEach(function (g) { var c = B.get(g); if (c) { hit++; B.set(g, c - 1); } });
      return 2 * hit / (A.length + Bl.length);
    }
    function contains(hay, needle) {
      if (!needle.length || needle.length > hay.length) return false;
      outer: for (var i = 0; i + needle.length <= hay.length; i++) {
        for (var j = 0; j < needle.length; j++) if (hay[i + j] !== needle[j]) continue outer;
        return true;
      }
      return false;
    }
    function score(qs, text) {
      var ts = norm(text);
      var q = toks(qs), t = toks(ts);
      if (!q.length || !t.length) return 0;
      if (qs === ts) return 1;
      var s = 0;
      if (contains(t, q)) s = Math.max(s, 0.6 + 0.35 * q.length / t.length);
      if (contains(q, t)) s = Math.max(s, 0.55 + 0.35 * t.length / q.length);
      var qset = new Set(q), inter = 0;
      new Set(t).forEach(function (w) { if (qset.has(w)) inter++; });
      var uni = new Set(q.concat(t)).size;
      s = Math.max(s, 0.85 * inter / uni);
      s = Math.max(s, 0.9 * dice(qs, ts));
      return s;
    }

    function docs() {
      var out = [document];
      var frames = document.querySelectorAll('iframe');
      for (var i = 0; i < frames.length; i++) {
        try { var d = frames[i].contentDocument; if (d && d.body) out.push(d); } catch (e) {}
      }
      return out;
    }
    var SEL = 'button, a, [role="button"], [role="option"], [role="radio"], [role="checkbox"], [role="tab"], [role="menuitem"], [role="link"], ' +
      'input[type="button"], input[type="submit"], input[type="radio"], input[type="checkbox"], label, [onclick], [tabindex], li, ' +
      '[class*="option"], [class*="choice"], [class*="answer"], [class*="btn"], [class*="button"], [class*="select"], [class*="card"], [class*="tile"]';
    function visible(el, doc) {
      var r = el.getBoundingClientRect();
      if (r.width < 2 || r.height < 2) return false;
      var w = doc.defaultView || window;
      var cs = w.getComputedStyle(el);
      if (cs.display === 'none' || cs.visibility === 'hidden' || parseFloat(cs.opacity) === 0 || cs.pointerEvents === 'none') return false;
      var vw = w.innerWidth, vh = w.innerHeight;
      if (r.right < 0 || r.bottom < 0 || r.left > vw || r.top > vh) return 'offscreen';
      var cx = Math.min(Math.max(r.left + r.width / 2, 0), vw - 1), cy = Math.min(Math.max(r.top + r.height / 2, 0), vh - 1);
      var top = doc.elementFromPoint(cx, cy);
      if (!top) return false;
      return (el.contains(top) || top.contains(el)) ? 'inview' : false;
    }
    function textOf(el) {
      var raw = (el.innerText != null ? el.innerText : el.textContent) || '';
      if (raw.length > 400) return '';
      var t = raw.replace(/\s+/g, ' ').trim();
      if (!t) t = el.getAttribute('aria-label') || el.getAttribute('title') || el.value || '';
      if (!t) { var img = el.querySelector && el.querySelector('img[alt]'); if (img) t = img.alt; }
      return String(t).replace(/\s+/g, ' ').trim().slice(0, 200);
    }
    function isOptionLike(el) {
      var role = el.getAttribute('role') || '';
      var cls = (typeof el.className === 'string' ? el.className : '').toLowerCase();
      var type = (el.type || '').toLowerCase();
      return ['option', 'radio', 'checkbox'].indexOf(role) >= 0 || type === 'radio' || type === 'checkbox' ||
        /option|choice|answer/.test(cls) || el.tagName === 'LABEL' || el.tagName === 'LI';
    }
    function collect() {
      var cands = [];
      docs().forEach(function (doc) {
        var w = doc.defaultView || window;
        var els = Array.prototype.slice.call(doc.querySelectorAll(SEL));
        var seen = new Set(els);
        var all = doc.getElementsByTagName('*');
        if (all.length < 5000) {
          for (var i = 0; i < all.length; i++) {
            var e = all[i];
            if (!seen.has(e) && w.getComputedStyle(e).cursor === 'pointer') { els.push(e); seen.add(e); }
          }
        }
        els.forEach(function (el) {
          if (el.disabled || el.getAttribute('aria-disabled') === 'true') return;
          var vis = visible(el, doc);
          if (!vis) return;
          var text = textOf(el);
          if (!text) return;
          cands.push({ el: el, text: text, doc: doc, r: el.getBoundingClientRect(), optionLike: isOptionLike(el), inView: vis === 'inview' });
        });
      });
      // Drop containers: elements that wrap other candidates with different text.
      var keep = cands.filter(function (c) {
        for (var i = 0; i < cands.length; i++) {
          var o = cands[i];
          if (o !== c && o.doc === c.doc && c.el !== o.el && c.el.contains(o.el) && o.text !== c.text) return false;
        }
        return true;
      });
      // Dedupe by text, preferring on-screen elements, then the first (outermost) one.
      var byText = new Map();
      keep.forEach(function (c) {
        var prev = byText.get(c.text);
        if (!prev || (c.inView && !prev.inView)) byText.set(c.text, c);
      });
      return Array.from(byText.values()).sort(function (a, b) { return (b.inView ? 1 : 0) - (a.inView ? 1 : 0); });
    }
    function optionOrder(cands) {
      return cands.filter(function (c) { return c.optionLike; })
        .sort(function (a, b) { return (a.r.top - b.r.top) || (a.r.left - b.r.left); });
    }
    function parseOrdinal(spoken) {
      var words = norm(spoken).split(' ').filter(function (w) { return FILLER.indexOf(w) < 0; });
      if (words.length === 2 && words[1] === '1' && ORD[words[0]] !== undefined) words = [words[0]]; // "first one"
      if (words.length !== 1) return null;
      var w = words[0];
      if (LETTER[w]) return { letter: LETTER[w] };
      if (ORD[w] !== undefined) return { index: ORD[w] };
      return null;
    }
    function doClick(c) {
      var el = c.el, w = c.doc.defaultView || window;
      try { el.scrollIntoView({ block: 'center', inline: 'nearest' }); } catch (e) {}
      var r = el.getBoundingClientRect(), x = r.left + r.width / 2, y = r.top + r.height / 2;
      var base = { bubbles: true, cancelable: true, composed: true, clientX: x, clientY: y, view: w, button: 0, buttons: 1 };
      var P = w.PointerEvent || w.MouseEvent, M = w.MouseEvent;
      function fire(type, Ctor, extra) {
        try { el.dispatchEvent(new Ctor(type, Object.assign({}, base, extra || {}))); } catch (e) {}
      }
      var pe = { pointerId: 1, pointerType: 'mouse', isPrimary: true };
      fire('pointerover', P, pe); fire('mouseover', M);
      fire('pointerdown', P, pe); fire('mousedown', M);
      try { if (el.focus) el.focus(); } catch (e) {}
      fire('pointerup', P, Object.assign({ buttons: 0 }, pe)); fire('mouseup', M, { buttons: 0 });
      if (typeof el.click === 'function') el.click(); else fire('click', M, { buttons: 0 });
    }
    function rank(cands, qs) {
      return cands.map(function (c) { return { c: c, s: score(qs, c.text) }; })
        .sort(function (a, b) { return (b.s - a.s) || ((b.c.inView ? 1 : 0) - (a.c.inView ? 1 : 0)); });
    }
    function topRect(c) {
      var r = c.el.getBoundingClientRect(), x = r.left, y = r.top;
      if (c.doc !== document) {
        var frames = document.querySelectorAll('iframe');
        for (var i = 0; i < frames.length; i++) {
          try { if (frames[i].contentDocument === c.doc) { var fr = frames[i].getBoundingClientRect(); x += fr.left; y += fr.top; break; } } catch (e) {}
        }
      }
      return { x: x, y: y, w: r.width, h: r.height };
    }
    function finish(pick, via, s, dryRun) {
      if (dryRun) return { ok: true, clicked: pick.text, via: via, score: s };
      try { pick.el.scrollIntoView({ block: 'center', inline: 'nearest' }); } catch (e) {}
      window.__vcTarget = pick;
      var rect = topRect(pick);
      var inside = rect.x + rect.w / 2 >= 0 && rect.y + rect.h / 2 >= 0 &&
        rect.x + rect.w / 2 <= window.innerWidth && rect.y + rect.h / 2 <= window.innerHeight;
      return { ok: true, clicked: pick.text, via: via, score: s, rect: rect, inside: inside };
    }
    function syntheticClick() {
      if (!window.__vcTarget) return 'no target';
      doClick(window.__vcTarget);
      return 'ok';
    }
    function run(spoken, dryRun) {
      var cands = collect();
      if (!cands.length) return { ok: false, reason: 'Nothing clickable on the page yet' };
      var qs = cleanQuery(spoken);
      if (!qs) return { ok: false, reason: 'Heard nothing usable' };

      var ord = parseOrdinal(spoken);
      if (ord && ord.letter) {
        var re = new RegExp('^' + ord.letter + '[.):\\-\\s]');
        for (var i = 0; i < cands.length; i++) {
          if (re.test(cands[i].text.toLowerCase())) return finish(cands[i], 'letter ' + ord.letter.toUpperCase(), 1, dryRun);
        }
        var opts = optionOrder(cands), idx = ord.letter.charCodeAt(0) - 97;
        if (opts[idx]) return finish(opts[idx], 'option ' + ord.letter.toUpperCase(), 1, dryRun);
      }
      if (ord && ord.index !== undefined) {
        var opts2 = optionOrder(cands);
        if (opts2[ord.index]) return finish(opts2[ord.index], 'option #' + (ord.index + 1), 1, dryRun);
      }

      var ranked = rank(cands, qs);
      if (ranked[0].s >= THRESH) return finish(ranked[0].c, 'text match', ranked[0].s, dryRun);

      var alias = ALIASES[qs];
      if (alias) {
        var r2 = rank(cands, norm(alias));
        if (r2[0].s >= THRESH) return finish(r2[0].c, 'alias for “' + alias + '”', r2[0].s, dryRun);
      }
      return { ok: false, reason: 'No button matches “' + spoken + '”',
        top: ranked.slice(0, 3).map(function (x) { return { text: x.c.text, score: x.s }; }) };
    }
    function listTexts() {
      return collect().slice(0, 60).map(function (c) { return (c.optionLike ? '◦ ' : '') + c.text; });
    }
    """#
}
