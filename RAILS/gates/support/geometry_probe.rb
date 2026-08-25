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
    DETERMINISM = File.read(File.join(__dir__, "geometry_probe/determinism.js")).freeze

    # The DOM walk. Returns a plain object; keep it self-contained so it can be
    # run against any page without helper injection.
    WALK = File.read(File.join(__dir__, "geometry_probe/walk.js")).freeze

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
