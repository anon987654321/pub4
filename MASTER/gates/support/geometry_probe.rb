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

      def master_port(root)
        rc = File.join(root, "OPENBSD", "etc", "rc.d", "master")
        File.read(rc)[/^PORT=(\d+)/, 1]&.to_i
      rescue SystemCallError
        nil
      end

      # master is not a RAILS app, so RAILS/apps.yml -- which is what Inventory
      # reads -- does not and should not describe it. Its port comes from the
      # rc.d script that actually binds it, rather than becoming a fourth copy
      # of 53187 beside rc.d, bin/triangle and relayd.conf.
      def app_ports(root: ROOT)
        Inventory.new(root: root).apps.to_h { |a| [a.name, a.port] }
                 .merge("master" => master_port(root))
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
    DETERMINISM = File.read(File.join(__dir__, "geometry_probe/determinism.js")).freeze

    # The DOM walk. Returns a plain object; keep it self-contained so it can be
    # run against any page without helper injection.
    WALK = File.read(File.join(__dir__, "geometry_probe/walk.js")).freeze

    # Which face paints æøå in each font stack the page wears. Its own
    # evaluation because it awaits document.fonts.load, and a face is only
    # measurable once it has loaded.
    GLYPHS = File.read(File.join(__dir__, "geometry_probe/glyphs.js")).freeze

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
    # after this, 20s of browser time does mean the page is wedged.
    # Net::HTTP directly rather than CrawlSupport.fetch: this warms a surface and
    # throws the response away, so it wants neither the redirect following nor
    # the body handling the shared client does. The Host still matters — the
    # vertical subdomains all resolve to the same port and are told apart by it —
    # and CrawlSupport.fetch does take a host: now, if this ever needs it.
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
      measure_current(cdp, surface)
    rescue CdpSession::Error => e
      { "error" => "#{e.class.name.split('::').last}: #{e.message}" }
    end

    # Measure the page already on screen. It never navigates or clears cookies,
    # so interactive states remain part of the same page composition.
    def self.measure_current(cdp, surface)
      return { "error" => "chrome error page — nothing answered at #{surface.url}" } if browser_error_page?(cdp)

      wait_for_fonts(cdp)
      cdp.evaluate(WALK).merge(GeometryType.probe(cdp)).merge(glyph_coverage(cdp)).merge("status" => cdp.status)
    rescue CdpSession::Error => e
      { "error" => "#{e.class.name.split('::').last}: #{e.message}" }
    end

    # Chrome answers a refused connection with its own page, and that page has a
    # DOM: measured on vm23 while amber and bsdports were shed, eight surfaces
    # were graded on Chrome's "site can't be reached" — its reload and details
    # buttons were reported as the app's controls, painting no state. A failed
    # navigation carries no navigation-timing status either, so `ok?` read the
    # zero as fine. The scheme is the tell.
    def self.browser_error_page?(cdp)
      cdp.evaluate("location.protocol === 'chrome-error:'") == true
    rescue CdpSession::Error
      false
    end

    # A glyph probe that breaks costs its own answer, not the surface's walk.
    def self.glyph_coverage(cdp)
      coverage = cdp.evaluate(GLYPHS, await_promise: true)
      coverage.is_a?(Hash) ? coverage : {}
    rescue CdpSession::Error => e
      warn "geometry_probe: glyph coverage failed (#{e.class.name.split('::').last}) — fallback faces not measured"
      {}
    end

    def self.ok?(payload)
      return false if payload["error"]

      status = payload["status"].to_i
      status.zero? || status.between?(200, 399)
    end

    # Fewer surfaces than this measured, while more were reachable, is a browser
    # session that dropped out part way rather than a floor that held. The four
    # journey gates (keyboard_flow, mobile_flow, occlusion, reflow) share the
    # line, so one flaking CDP session cannot read green in one of them and
    # inconclusive in another. A run with fewer reachable surfaces than this has
    # to measure all of them.
    MIN_MEASURED_SURFACES = 3

    def self.too_few_measured?(measured, reachable)
      measured < [MIN_MEASURED_SURFACES, reachable].min
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
