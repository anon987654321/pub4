# frozen_string_literal: true

module Deploy
  # The page-side scripts of the stress states, kept as data. Single-quoted
  # heredocs: in a double-quoted one Ruby reads the regex escape \s as a space.
  # Every script is one expression that returns JSON-safe values, so the same
  # text runs through CDP and through a WebDriver execute call.
  module StressScripts
    # A short selector a human can grep for: tag, first class or id, position.
    PATH_JS = <<~'JS'
      const path = (el) => {
        const parts = [];
        for (let n = el; n && n.nodeType === 1 && n !== document.body && parts.length < 4; n = n.parentElement) {
          let idx = 1;
          for (let s = n.previousElementSibling; s; s = s.previousElementSibling) if (s.tagName === n.tagName) idx++;
          const cls = (n.getAttribute("class") || "").trim().split(/\s+/)[0];
          parts.unshift(n.tagName.toLowerCase() + (n.id ? "#" + n.id : cls ? "." + cls : "") + ":nth-of-type(" + idx + ")");
        }
        return parts.join(">");
      };
    JS

    # Which stress emulations the app answers to: a state the stylesheet has no
    # rule for would only photograph the default twice.
    SUPPORT_JS = <<~'JS'
      (() => {
        const found = { dark: false, reduced_motion: false };
        const walk = (rules) => {
          for (const rule of rules) {
            if (rule.media && /prefers-color-scheme:\s*dark/.test(rule.media.mediaText)) found.dark = true;
            if (rule.media && /prefers-reduced-motion/.test(rule.media.mediaText)) found.reduced_motion = true;
            if (rule.cssRules) walk(rule.cssRules);
          }
        };
        for (const sheet of document.styleSheets) {
          try { walk(sheet.cssRules); } catch (e) { /* cross-origin sheet: unreadable, not absent */ }
        }
        if (document.querySelector('meta[name="color-scheme"]')) found.dark = true;
        return found;
      })()
    JS

    # Longest text nodes get their longest word replaced; node data only, so the
    # element tree is untouched and a wrap-safe layout still wraps.
    COMPOUND_JS = <<~'JS'.freeze
      ((words, limit) => {
        const skip = "script,style,noscript,textarea,svg,head,[hidden],[data-master-composition-ignore='true']";
        const walker = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT);
        const nodes = [];
        for (let n = walker.nextNode(); n; n = walker.nextNode()) {
          const el = n.parentElement;
          if (!el || el.closest(skip)) continue;
          const text = n.data.trim();
          if (text.length < 4 || /^[\d\s.,:%\/-]+$/.test(text)) continue;
          const r = el.getBoundingClientRect();
          if (r.width < 1 || r.height < 1 || getComputedStyle(el).visibility === "hidden") continue;
          nodes.push(n);
        }
        nodes.sort((a, b) => b.data.trim().length - a.data.trim().length);
        const changed = [];
        nodes.slice(0, limit).forEach((n, i) => {
          const parts = n.data.split(/(\s+)/);
          let at = 0;
          parts.forEach((p, j) => { if (p.trim().length > parts[at].trim().length) at = j; });
          const before = parts[at].trim();
          parts[at] = parts[at].replace(before, words[i % words.length]);
          n.data = parts.join("");
          changed.push(before.slice(0, 24));
        });
        return { replaced: changed.length, originals: changed };
      })(__WORDS__, __LIMIT__)
    JS

    # The largest repeated structure (or a list-shaped container, even an empty
    # one), tagged so later scripts find it again after the DOM changes.
    LIST_DETECT_JS = <<~'JS'.sub("__PATH__") { PATH_JS }.freeze
      (() => {
        __PATH__
        const root = document.querySelector("main, [role=main]") || document.body;
        const shape = /(^|[-_ ])(list|feed|grid|cards?|items?|posts?|results?|messages?|comments?|threads?|listings?|gallery|catalog|products?|timeline|stream)([-_ ]|$)/i;
        const barred = "header,nav,footer,select,svg,[role=menu],[role=tablist],[role=navigation],[data-master-composition-ignore='true']";
        const sig = (el) => el.tagName + "." + ((el.getAttribute("class") || "").trim().split(/\s+/)[0] || "");
        let best = null;
        document.querySelectorAll("[data-master-stress-list]").forEach((e) => e.removeAttribute("data-master-stress-list"));
        for (const parent of [root, ...root.querySelectorAll("*")]) {
          if (parent.closest(barred) || getComputedStyle(parent).display === "none") continue;
          const groups = {};
          for (const kid of parent.children) {
            if (/^(SCRIPT|STYLE|TEMPLATE)$/.test(kid.tagName)) continue;
            (groups[sig(kid)] = groups[sig(kid)] || []).push(kid);
          }
          const top = Object.entries(groups).sort((a, b) => b[1].length - a[1].length)[0];
          const size = top ? top[1].length : 0;
          const semantic = /^(UL|OL|TBODY|DL)$/.test(parent.tagName) || parent.getAttribute("role") === "list" ||
            shape.test((parent.getAttribute("class") || "") + " " + parent.id);
          if (size < 3 && !semantic) continue;
          const area = parent.getBoundingClientRect().width * parent.getBoundingClientRect().height;
          const score = size * 1e6 + Math.min(area, 999999);
          if (!best || score > best.score) best = { parent, size, key: top ? top[0] : "", score };
        }
        if (!best) return null;
        best.parent.setAttribute("data-master-stress-list", best.key);
        return { selector: path(best.parent), count: best.size, signature: best.key };
      })()
    JS

    # Prune or clone the tagged list's repeated children to exactly n.
    LIST_SET_JS = <<~'JS'.freeze
      ((n) => {
        const parent = document.querySelector("[data-master-stress-list]");
        if (!parent) return null;
        const key = parent.getAttribute("data-master-stress-list");
        const sig = (el) => el.tagName + "." + ((el.getAttribute("class") || "").trim().split(/\s+/)[0] || "");
        const kids = Array.from(parent.children).filter((k) => sig(k) === key);
        const before = kids.length;
        if (n < before) kids.slice(n).forEach((k) => k.remove());
        if (n > before && before > 0) {
          let last = kids[kids.length - 1];
          for (let i = before; i < n; i++) {
            const copy = kids[i % before].cloneNode(true);
            copy.removeAttribute("id");
            copy.querySelectorAll("[id]").forEach((e) => e.removeAttribute("id"));
            last.after(copy);
            last = copy;
          }
        }
        return { before, after: Math.min(n, before) + (before > 0 ? Math.max(0, n - before) : 0) };
      })(__COUNT__)
    JS
  end
end
