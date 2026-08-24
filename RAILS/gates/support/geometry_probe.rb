# frozen_string_literal: true

require "net/http"
require "yaml"
require_relative "../../../OPENBSD/lib/deploy_inventory"
require_relative "../../tools/crawl_support"
require_relative "cdp_session"
require_relative "brgen_vertical_surfaces"
require_relative "geometry_type" # worn-type walk; see GeometryType.probe

module Deploy
  # The shared measurement substrate: one DOM walk per surface returning what
  # the browser actually laid out, not what the stylesheet says it should.
  #
  # Everything downstream (Fitts, occlusion, contrast, overflow, rhythm, token
  # conformance, snapshots, reflow, keyboard order) reads this payload instead
  # of grepping SCSS. That is the whole point: design_metrics_gate could only
  # assert "_nav.scss contains the string min-height: 44px"; this asserts the
  # rendered box is 44px tall and that nothing is sitting on top of it.
  class GeometryProbe
    ROOT = File.expand_path("../../..", __dir__)
    DATA = File.join(File.expand_path("..", __dir__), "data", "geometry_surfaces.yml")

    Surface = Struct.new(:app, :label, :host, :path, :viewport, :width, :height, :snapshot, :port, :profile, keyword_init: true) do
      def id = "#{app}/#{label}/#{viewport}"

      # A surface without a declared host is probed over loopback. Only brgen
      # needs its real Host — its vertical routing keys off the subdomain, and
      # Rails' development host authorization rejects vanity domains the app
      # has not allowlisted, which renders a 403 page that measures perfectly
      # and means nothing.
      def authority = host || "127.0.0.1:#{port}"
      def url = "http://#{authority}#{path}"
    end

    class << self
      def config(path = DATA)
        @config ||= {}
        @config[path] ||= YAML.safe_load_file(path)
      end

      def viewports(path = DATA) = config(path).fetch("viewports")
      def reflow_widths(path = DATA) = Array(config(path)["reflow_widths"])
      def volatile_selectors(path = DATA) = Array(config(path)["volatile_selectors"])

      # Every declared surface × viewport, brgen verticals included.
      def surfaces(path = DATA, root: ROOT)
        cfg = config(path)
        vps = cfg.fetch("viewports")
        ports = app_ports(root: root)
        rows = []

        if cfg["include_brgen_verticals"]
          wanted = Array(cfg["brgen_vertical_viewports"])
          BrgenVerticalSurfaces::SURFACES.each do |s|
            wanted.each do |vp|
              w, h = vps.fetch(vp)
              rows << Surface.new(app: "brgen", label: s[:label], host: s[:host], path: s[:path],
                                  viewport: vp, width: w, height: h, snapshot: true,
                                  port: ports["brgen"], profile: s[:profile])
            end
          end
        end

        Array(cfg["surfaces"]).each do |s|
          Array(s["viewports"]).each do |vp|
            w, h = vps.fetch(vp)
            app = s.fetch("app")
            rows << Surface.new(app: app, label: s.fetch("label"), host: s["host"],
                                path: s.fetch("path"), viewport: vp, width: w, height: h,
                                snapshot: !!s["snapshot"], port: ports[app],
                                profile: s["profile"])
          end
        end
        filter(rows)
      end

      # GATE_SURFACES=brgen/core,amber narrows a run to matching app/label
      # prefixes — for iterating on one surface without a 39-cell sweep.
      def filter(rows)
        raw = ENV["GATE_SURFACES"].to_s.strip
        return rows if raw.empty?

        wanted = raw.split(",").map(&:strip).reject(&:empty?)
        rows.select { |s| wanted.any? { |w| "#{s.app}/#{s.label}".start_with?(w) || s.app == w } }
      end

      # host -> "127.0.0.1:port" for Chrome's --host-resolver-rules, so the
      # marketplace/dating/messenger subdomains are reachable in a browser at
      # all. Selenium could not set a Host header, which is why the existing
      # browser probe skips markedsplass entirely (design_metrics_gate.rb:317).
      def host_map(root: ROOT, path: DATA)
        map = {}
        surfaces(path, root: root).each do |s|
          map[s.host] ||= "127.0.0.1:#{s.port}" if s.host && s.port
        end
        map
      end

      def app_ports(root: ROOT)
        Inventory.new(root: root).apps.to_h { |a| [a.name, a.port] }
      end

      def app_up?(app, root: ROOT)
        port = app_ports(root: root)[app]
        port && CrawlSupport.port_open?("127.0.0.1", port)
      end
    end

    # Determinism harness. Runs before any page script on every navigation.
    #
    # Deliberately does NOT freeze Date.now: Turbo, ActionCable and Stimulus
    # timers all depend on a moving clock, and stopping it wedges the page.
    # Seeding Math.random is safe and removes the main source of render noise.
    DETERMINISM = <<~JS
      (() => {
        let seed = 0x2545F491;
        Math.random = () => {
          seed ^= seed << 13; seed ^= seed >>> 17; seed ^= seed << 5;
          return ((seed >>> 0) % 1000000) / 1000000;
        };
        const freeze = () => {
          const style = document.createElement('style');
          style.setAttribute('data-gate-determinism', '');
          style.textContent = `*,*::before,*::after{
            animation-duration:0s !important;animation-delay:0s !important;
            animation-iteration-count:1 !important;
            transition-duration:0s !important;transition-delay:0s !important;
            caret-color:transparent !important;scroll-behavior:auto !important;}`;
          (document.head || document.documentElement).appendChild(style);
        };
        if (document.head) freeze();
        else document.addEventListener('DOMContentLoaded', freeze, { once: true });
      })();
    JS

    # The DOM walk. Returns a plain object; keep it self-contained so it can be
    # run against any page without helper injection.
    WALK = <<~JS
      (() => {
        const MAX = 2000;
        const de = document.documentElement;
        const vw = de.clientWidth, vh = de.clientHeight;

        const INTERACTIVE_SEL = [
          'a[href]', 'button', 'input:not([type=hidden])', 'select', 'textarea',
          'summary', '[role=button]', '[role=link]', '[role=tab]', '[role=switch]',
          '[role=menuitem]', '[role=checkbox]', '[onclick]'
        ].join(',');

        // Anything CSS can express, resolved to sRGB by the browser itself.
        //
        // This used to match rgba?() only. Chrome keeps oklch() in computed
        // style rather than converting it, so every oklch colour parsed as null
        // and the caller substituted opaque black — which is how the gate came
        // to report brgen/takeaway as "#000000 on #1a1a1a = 1.21" for text that
        // is actually a legible red. _vertical_takeaway.scss defines its accents
        // in oklch, so every takeaway contrast finding was fictional, and
        // fictional failures are worse than none: they train you to skim past
        // the real ones sitting in the same list.
        const _swatch = document.createElement('canvas');
        _swatch.width = _swatch.height = 1;
        const _swatchCtx = _swatch.getContext('2d', { willReadFrequently: true });
        const parseRgb = (s) => {
          const str = String(s).trim();
          if (!str || str === 'transparent') return null;
          const m = str.match(/rgba?\\(([^)]+)\\)/);
          if (m) {
            const p = m[1].split(/[,\\s\\/]+/).filter(Boolean).map(Number);
            if (p.length >= 3 && !p.some(Number.isNaN)) {
              return { r: p[0], g: p[1], b: p[2], a: p.length > 3 ? p[3] : 1 };
            }
          }
          if (!_swatchCtx) return null;
          try {
            // fillStyle silently ignores a value it cannot parse, so paint over
            // a known sentinel and treat "unchanged" as unsupported rather than
            // reading back the sentinel as if it were the real colour.
            _swatchCtx.clearRect(0, 0, 1, 1);
            _swatchCtx.fillStyle = '#010203';
            _swatchCtx.fillStyle = str;
            if (_swatchCtx.fillStyle === '#010203' && !/^#010203$/i.test(str)) return null;
            _swatchCtx.fillRect(0, 0, 1, 1);
            const d = _swatchCtx.getImageData(0, 0, 1, 1).data;
            return { r: d[0], g: d[1], b: d[2], a: d[3] / 255 };
          } catch (_) {
            return null;
          }
        };
        const over = (fg, bg) => ({
          r: fg.r * fg.a + bg.r * (1 - fg.a),
          g: fg.g * fg.a + bg.g * (1 - fg.a),
          b: fg.b * fg.a + bg.b * (1 - fg.a),
          a: 1
        });
        const hex = (c) => c ? '#' + [c.r, c.g, c.b].map(v =>
          Math.max(0, Math.min(255, Math.round(v))).toString(16).padStart(2, '0')).join('') : null;

        // Composite every ancestor background down to an opaque colour, the
        // way the compositor does. var()/oklch/color-mix all arrive here
        // already resolved, which is exactly what the static hex parser in
        // design_metrics.rb has to give up on.
        const effectiveBg = (el) => {
          let node = el, acc = null;
          while (node && node.nodeType === 1) {
            const c = parseRgb(getComputedStyle(node).backgroundColor);
            if (c && c.a > 0) acc = acc ? over(acc, c) : c;
            if (acc && acc.a >= 0.999) return acc;
            node = node.parentElement;
          }
          const page = parseRgb(getComputedStyle(de).backgroundColor);
          const base = (page && page.a >= 0.999) ? page : { r: 255, g: 255, b: 255, a: 1 };
          return acc ? over(acc, base) : base;
        };

        // Runtime state classes must never reach a selector key. body carries
        // stimulus-reflex-connected / -disconnected depending on whether the
        // websocket has attached yet, and because keys are ancestor paths that
        // one class flipped the key of every element on the page — which reads
        // as "everything was removed and re-added" on the next comparison.
        //
        // network-/battery-/power- are the same defect one step worse: those are
        // toggled on <html> from the *measured* connection, battery and CPU
        // (network_aware_controller, battery_aware_controller), so they key on
        // the machine and the moment the probe ran rather than on anything in
        // the tree. Missing them put html.network-slow into the ancestor path of
        // every element on every page — 78 of 436 drift lines in one run were
        // the same element reported as both removed and added. -hidden was
        // already covered by the suffix group, which is why page-hidden and
        // chrome-hidden never showed up here.
        // next/prev/duplicate are carousel position, which moves on its own:
        // Swiper writes swiper-slide-next onto whichever slide is currently
        // queued, so one autoplay tick between two runs of the snapshot gate
        // renamed a slide that nothing in the tree had touched. -active was
        // already covered by this group, which is why only its siblings showed.
        const VOLATILE_CLASS = /^(ng-|js-|is-|has-|turbo-|network-|battery-|power-)|(-|^)(connected|disconnected|loading|loaded|ready|active|open|closed|revealed|hidden|visible|scrolled|pending|selected|next|prev|duplicate)$/;
        const classSig = (el) => {
          const cls = (el.getAttribute('class') || '').trim().split(/\\s+/)
            .filter(c => c && !VOLATILE_CLASS.test(c)).slice(0, 3);
          return cls.length ? '.' + cls.join('.') : '';
        };
        const selFor = (el) => {
          if (el.id) return '#' + el.id;
          const parts = [];
          let node = el, depth = 0;
          while (node && node.nodeType === 1 && depth < 4) {
            if (node.id) { parts.unshift('#' + node.id); break; }
            parts.unshift(node.tagName.toLowerCase() + classSig(node));
            node = node.parentElement; depth++;
          }
          return parts.join('>');
        };

        const seen = Object.create(null);
        const keyFor = (sel) => {
          seen[sel] = (seen[sel] || 0) + 1;
          return seen[sel] === 1 ? sel : sel + '[' + seen[sel] + ']';
        };

        const out = [];
        const colors = Object.create(null);
        const overflow = [];
        const all = document.querySelectorAll('body *');

        for (let i = 0; i < all.length && out.length < MAX; i++) {
          const el = all[i];
          const cs = getComputedStyle(el);
          if (cs.display === 'none' || cs.visibility === 'hidden') continue;
          const r = el.getBoundingClientRect();
          const area = r.width * r.height;
          const opacity = parseFloat(cs.opacity);

          const interactive = el.matches(INTERACTIVE_SEL) ||
            (el.hasAttribute('tabindex') && el.getAttribute('tabindex') !== '-1');
          const ownText = Array.from(el.childNodes)
            .filter(n => n.nodeType === 3).map(n => n.textContent.trim()).join(' ').trim();
          const landmark = /^(header|nav|main|footer|aside|section|form|h1|h2|h3)$/.test(el.tagName.toLowerCase());

          // WCAG 2.5.8 exempts links flowing inline inside a sentence — they
          // are not touch targets and counting them buries the real ones.
          const parentText = el.parentElement
            ? Array.from(el.parentElement.childNodes)
                .filter(n => n.nodeType === 3).map(n => n.textContent.trim()).join('').trim()
            : '';
          const inlineInText = cs.display.startsWith('inline') && !cs.display.startsWith('inline-') &&
            parentText.length > 0;

          if (!interactive && !ownText && !landmark) continue;
          if (area <= 0 || opacity === 0) {
            if (interactive) out.push({
              key: keyFor(selFor(el)), tag: el.tagName.toLowerCase(), interactive: true,
              visible: false, rect: { x: 0, y: 0, w: 0, h: 0 }, text: ownText.slice(0, 60)
            });
            continue;
          }

          // No black default. Substituting a colour we could not read invents a
          // contrast finding out of nothing; leaving fg null makes the caller
          // skip the check, which is the honest answer for a colour the probe
          // genuinely cannot resolve.
          const fg = parseRgb(cs.color);
          const bg = effectiveBg(el);
          const fgOpaque = fg ? (fg.a >= 0.999 ? fg : over(fg, bg)) : null;

          if (ownText && fgOpaque) {
            const ck = hex(fgOpaque);
            if (ck) colors[ck] = (colors[ck] || 0) + 1;
          }

          // Hit test the centre: if something else owns that pixel the control
          // is unclickable no matter how big its box is.
          let hit = 'none';
          const cx = r.left + r.width / 2, cy = r.top + r.height / 2;
          if (interactive && cx >= 0 && cy >= 0 && cx <= vw && cy <= vh) {
            const top = document.elementFromPoint(cx, cy);
            if (!top) hit = 'none';
            else if (top === el) hit = 'self';
            else if (el.contains(top)) hit = 'descendant';
            else if (top.contains(el)) hit = 'ancestor';
            else {
              // Content resting under fixed/sticky chrome at scroll 0 is not
              // unclickable — scrolling moves it out. Only a blocker in normal
              // flow is a real dead zone.
              //
              // The anchor must be one the blocker has and the element does
              // NOT: these apps wrap everything in a fixed .app-shell, so
              // "does the element have a fixed ancestor" is true for the whole
              // page and would classify every real occlusion as chrome.
              const anchorOf = (node) => {
                for (let n = node; n && n.nodeType === 1; n = n.parentElement) {
                  const p = getComputedStyle(n).position;
                  if (p === 'fixed' || p === 'sticky') return n;
                }
                return null;
              };
              const blockerAnchor = anchorOf(top);
              hit = (blockerAnchor && !blockerAnchor.contains(el))
                ? 'under_chrome:' + selFor(top).slice(0, 60)
                : 'blocked:' + selFor(top).slice(0, 80);
            }
          } else if (interactive) {
            hit = 'offscreen';
          }

          // Only right-side spill counts. An element parked at left:-300 is the
          // standard closed-drawer idiom, not a layout break, and the document
          // scrollWidth below is the authoritative signal either way.
          if (r.right > vw + 1 && r.width > 4) {
            overflow.push({ sel: selFor(el), right: Math.round(r.right), width: Math.round(r.width) });
          }

          out.push({
            key: keyFor(selFor(el)),
            tag: el.tagName.toLowerCase(),
            role: el.getAttribute('role') || null,
            aria: el.getAttribute('aria-label') || null,
            text: ownText.slice(0, 60),
            rect: { x: Math.round(r.left), y: Math.round(r.top), w: Math.round(r.width), h: Math.round(r.height) },
            // The rounded rect above is what every existing check reads, and
            // rounding is exactly what hides a subpixel defect: an element at
            // x=12.5 reports 13 and looks aligned. Two decimals is past what a
            // device pixel ratio of 3 can resolve, so anything left here is a
            // real fractional position and not float noise.
            frect: {
              x: Math.round(r.left * 100) / 100,
              y: Math.round(r.top * 100) / 100,
              w: Math.round(r.width * 100) / 100,
              h: Math.round(r.height * 100) / 100
            },
            color: hex(fgOpaque),
            bg: hex(bg),
            font_size: Math.round(parseFloat(cs.fontSize) * 10) / 10,
            font_weight: cs.fontWeight,
            line_height: cs.lineHeight === 'normal' ? null : Math.round(parseFloat(cs.lineHeight) * 10) / 10,
            position: cs.position,
            display: cs.display,
            text_align: cs.textAlign,
            // Needed to tell a text field from a submit button: both are
            // <input>, only one takes a caret, and only one triggers the iOS
            // focus zoom. The selector alone cannot say which.
            input_type: el.tagName === 'INPUT' ? (el.getAttribute('type') || 'text').toLowerCase() : null,
            z: cs.zIndex === 'auto' ? null : cs.zIndex,
            interactive: interactive,
            inline_in_text: inlineInText,
            visible: true,
            // Laid out but parked outside the viewport — a closed drawer or a
            // carousel slide. Still a real element with real styles; just not
            // on the first screen, which callers should say out loud.
            onscreen: r.right > 0 && r.left < vw && r.bottom > 0,
            hit: hit
          });
        }

        // Rendered vertical gaps between consecutive block siblings — the 8px
        // rhythm as laid out, not as declared in a stylesheet that may cascade
        // away or be overridden at this breakpoint.
        const gaps = [];
        const containers = document.querySelectorAll('main, main *, [role=main], .feed, .deal-grid');
        for (let i = 0; i < containers.length && gaps.length < 400; i++) {
          const kids = Array.from(containers[i].children).filter(k => {
            const cs = getComputedStyle(k);
            if (cs.display === 'none' || cs.position === 'absolute' || cs.position === 'fixed') return false;
            if (cs.display.startsWith('inline') && !cs.display.startsWith('inline-')) return false;
            const kr = k.getBoundingClientRect();
            // Major stacked blocks only. Hairlines and inline runs produce
            // sub-4px "gaps" that are borders and leading, not rhythm.
            return kr.height > 24 && kr.width > vw * 0.5;
          });
          for (let j = 0; j + 1 < kids.length; j++) {
            const a = kids[j].getBoundingClientRect(), b = kids[j + 1].getBoundingClientRect();
            const g = Math.round(b.top - a.bottom);
            if (g >= 4 && g <= 128) gaps.push({ gap: g, sel: selFor(kids[j + 1]) });
          }
        }

        // Peer choices per navigation group, for Hick's law and chunking. A
        // count is only meaningful among *siblings* offered at the same moment,
        // so this counts direct interactive children of each menu-ish container
        // rather than every link inside it.
        const groups = [];
        document.querySelectorAll('nav, [role=navigation], [role=menu], [role=tablist], .tab-bar')
          .forEach(container => {
            const cs = getComputedStyle(container);
            if (cs.display === 'none' || cs.visibility === 'hidden') return;
            const r = container.getBoundingClientRect();
            if (r.width < 1 || r.height < 1) return;
            const choices = Array.from(container.querySelectorAll('a[href], button, [role=tab], [role=menuitem]'))
              .filter(k => {
                const kcs = getComputedStyle(k);
                if (kcs.display === 'none' || kcs.visibility === 'hidden') return false;
                const kr = k.getBoundingClientRect();
                return kr.width > 0 && kr.height > 0;
              });
            // Chunking is the other prescribed remedy for Hick, alongside a
            // scrolling rail: a bar that splits its entries into labelled
            // role=group sections asks the reader to choose within a group, not
            // among every link at once. Reported so the gate can judge the
            // largest chunk rather than the container total — brgen groups its
            // eleven verticals as 4 and 7, and counting 11 credited neither.
            const chunks = [...container.querySelectorAll('[role=group]')]
              .map(g => g.querySelectorAll('a[href], button, [role=tab], [role=menuitem]').length)
              .filter(n => n > 0);
            groups.push({ sel: selFor(container), count: choices.length, chunks,
                          scrollable: container.scrollWidth > container.clientWidth + 4 });
          });

        // Gestalt proximity, measured correctly: the space *between an element's
        // own children* against the space between that element and the next one.
        // That is what the eye compares. Summing the element's top and bottom
        // padding — the first version of this — asks a different question and
        // answers it wrongly: a hero with 40px above and below its content and
        // 48px to the next section reported "80 > 48" and was flagged, when its
        // children sit 32px apart inside a 48px separation, which is right.
        const proximity = [];
        const measuredGap = (a, b) => Math.round(b.getBoundingClientRect().top - a.getBoundingClientRect().bottom);
        const laidOut = el => {
          const cs = getComputedStyle(el);
          if (cs.display === 'none' || cs.position === 'absolute' || cs.position === 'fixed') return false;
          return el.getBoundingClientRect().height > 4;
        };
        for (let i = 0; i < containers.length && proximity.length < 200; i++) {
          const kids = Array.from(containers[i].children).filter(k => {
            const kr = k.getBoundingClientRect();
            return laidOut(k) && kr.height > 24 && kr.width > vw * 0.5;
          });
          for (let j = 0; j + 1 < kids.length; j++) {
            const a = kids[j], b = kids[j + 1];
            const external = measuredGap(a, b);
            if (external < 0 || external > 128) continue;
            // The widest gap between a's own consecutive children is its
            // internal spacing — the distance the eye reads as "same group".
            const inner = Array.from(a.children).filter(laidOut);
            let internal = 0;
            for (let k = 0; k + 1 < inner.length; k++) {
              const g = measuredGap(inner[k], inner[k + 1]);
              if (g > internal && g <= 128) internal = g;
            }
            if (internal > 0) proximity.push({ sel: selFor(a), pad: internal, gap: external });
          }
        }

        return {
          vw: vw, vh: vh,
          title: document.title,
          groups: groups,
          proximity: proximity,
          scroll_width: de.scrollWidth,
          client_width: de.clientWidth,
          h1_count: document.querySelectorAll('h1').length,
          landmarks: {
            main: !!document.querySelector('main, [role=main], #main-content'),
            nav: !!document.querySelector('nav, [role=navigation]'),
            skip: !!document.querySelector('a[href="#main-content"], .skip-link')
          },
          elements: out,
          colors: colors,
          overflow: overflow,
          gaps: gaps
        };
      })()
    JS

    def self.available? = CdpSession.available?

    # Probe a list of surfaces, yielding [surface, payload] as each completes.
    # One browser for the whole run; one navigation per surface.
    def self.each_payload(surfaces, root: ROOT)
      return enum_for(:each_payload, surfaces, root: root) unless block_given?

      with_browser(root: root) do |cdp|
        surfaces.each { |surface| yield surface, walk(cdp, surface) }
      end
    end

    # One browser, caller drives navigation. Gates that need more than a single
    # load per surface (idempotence, back-button, tab order, width sweeps) use
    # this rather than paying for a browser launch each.
    def self.with_browser(root: ROOT, warm: surfaces(DATA, root: root))
      warm_surfaces(warm)
      CdpSession.open(host_map: host_map(root: root)) do |cdp|
        cdp.on_new_document(DETERMINISM)
        yield cdp
      end
    end

    # A plain GET per host before the browser opens.
    #
    # The browser budget is 20s, which is generous for a page and nowhere near
    # enough for a development-mode Rails app compiling a surface for the first
    # time. Measured cold, brgen's front page reaches readyState complete in
    # ~13s and can exceed 20 under load; warm it is 3-6s. So keyboard_flow and
    # journey_invariant reported "unreachable" for surfaces that were serving
    # 200 to curl the whole time, and the failure looked like a host-resolution
    # bug -- the vertical subdomains are Host-mapped, so that is the obvious
    # suspect and it was never the cause.
    #
    # Warming here rather than raising the timeout keeps the budget meaningful:
    # after this, 20s of browser time really does mean the page is wedged.
    # Net::HTTP rather than CrawlSupport.fetch, which cannot set a Host header --
    # and the Host is the whole point for the vertical subdomains, which all
    # resolve to the same port and are told apart by it.
    def self.warm_surfaces(rows)
      Array(rows).map { |s| [s.host, s.port] }.uniq.each do |host, port|
        next unless host && port

        Net::HTTP.start("127.0.0.1", port, open_timeout: 5, read_timeout: 60) do |http|
          http.request(Net::HTTP::Get.new("/", { "Host" => host }))
        end
      rescue StandardError
        # Unreachable here is not this method's business to report; the probe
        # that follows records it against the surface it belongs to.
        nil
      end
    end

    # Pinned so a measurement does not depend on the machine doing the measuring.
    # amber negotiates its language from Accept-Language and remembers the answer
    # in the session (LocalizedRequest), so an unpinned probe recorded a Norwegian
    # page one run and an English one the next -- the whole layout differed, not
    # only the title, and no amount of re-recording could settle it. English
    # because that is what the committed baselines already hold.
    PROBE_HEADERS = { "Accept-Language" => "en-US,en;q=0.9" }.freeze

    def self.walk(cdp, surface, width: nil, height: nil)
      w = width || surface.width
      h = height || surface.height
      cdp.viewport(w, h, mobile: w < 500)
      cdp.headers(PROBE_HEADERS)
      # A session cookie carried from the previously measured surface is the
      # other half of the same problem: it outranks Accept-Language, so one page
      # visited with a stale locale choice re-answers in that language.
      cdp.clear_cookies
      cdp.navigate(surface.url)
      wait_for_fonts(cdp)
      # Status first. A 403 host-authorization page or a 500 renders a
      # perfectly measurable DOM that has nothing to do with the design, and
      # grading it produces confident nonsense.
      cdp.evaluate(WALK).merge(GeometryType.probe(cdp)).merge("status" => cdp.status)
    rescue CdpSession::Error => e
      { "error" => "#{e.class.name.split('::').last}: #{e.message}" }
    end

    def self.ok?(payload)
      return false if payload["error"]

      status = payload["status"].to_i
      status.zero? || status.between?(200, 399)
    end

    # Web fonts change every metric on the page. Measuring before they land is
    # the single biggest source of flake in layout assertions.
    def self.wait_for_fonts(cdp, timeout: 3)
      deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout
      loop do
        ready = begin
          cdp.evaluate("document.fonts ? document.fonts.status === 'loaded' : true")
        rescue CdpSession::Error
          true
        end
        return true if ready
        return false if Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline

        sleep 0.05
      end
    end

    # Only probe surfaces whose app is actually listening.
    def self.reachable(surfaces, root: ROOT)
      ports = app_ports(root: root)
      surfaces.select do |s|
        port = ports[s.app]
        port && CrawlSupport.port_open?("127.0.0.1", port)
      end
    end

    def self.unreachable_apps(surfaces, root: ROOT)
      ports = app_ports(root: root)
      surfaces.map(&:app).uniq.reject do |app|
        port = ports[app]
        port && CrawlSupport.port_open?("127.0.0.1", port)
      end
    end
  end
end
