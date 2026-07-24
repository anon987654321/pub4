# frozen_string_literal: true

require "net/http"
require "uri"
require_relative "../../../OPENBSD/lib/deploy_inventory"
require_relative "../../../OPENBSD/lib/gate_result"
require_relative "../../crawl_support"
require_relative "brgen_vertical_surfaces"
require_relative "dom_surface_schema"

module Deploy
  # First-screen contract + hierarchy + touch geometry (MASTER layout_rules / Fitts).
  class LayoutGeometryGate
    ROOT = File.expand_path("../../..", __dir__)
    RAILS = File.join(ROOT, "RAILS")

    # Map surface labels (from SURFACES / verticals) → schema ids.
    # live_first_screen builds label as "app/label" (e.g. brgen/vertical_marketplace).
    SCHEMA_FOR_LABEL = {
      "vertical_marketplace" => "marketplace_listings",
      "vertical_marketplace_cart" => "marketplace_cart",
      "vertical_live" => "live_feed",
      "vertical_dating" => "dating_home",
      "vertical_messenger" => "messenger_inbox",
      "vertical_core" => "brgen_home",
      "core_ip" => "brgen_home",
      "core" => "brgen_home",
      "marketplace" => "marketplace_listings",
      "marketplace_cart" => "marketplace_cart",
      "live" => "live_feed",
      "dating" => "dating_home",
      "messenger" => "messenger_inbox",
    }.freeze

    BASE_SURFACES = [
      { app: "brgen", port_key: "brgen", path: "/", host: nil, label: "core_ip",
        first_screen: [%r{skip-link|Skip to main}i, %r{<main\b|main-content}i, %r{<h1\b}i],
        css_touch: [%w[brgen/app/assets/stylesheets/_nav.scss min-height:\s*44px],
                    %w[brgen/app/assets/stylesheets/_marketplace.scss min-height:\s*44px]] },
      { app: "amber", port_key: "amber", path: "/", host: nil,
        first_screen: [%r{skip-link|Skip to main}i, %r{main-content|<main\b}i, %r{Amber|jox|Signup|Login|wardrobe}i],
        css_touch: [%w[amber/app/assets/stylesheets/_jsfiddle_chrome.scss jox-buttons]] },
      { app: "bsdports", port_key: "bsdports", path: "/", host: nil,
        first_screen: [%r{skip-link|Skip to main}i, %r{main-content|<main\b}i, %r{BSD|port}i],
        css_touch: [%w[bsdports/app/assets/stylesheets/application.scss --font]] },
      { app: "bsdports", port_key: "bsdports", path: "/ports", host: nil, label: "ports",
        first_screen: [%r{search|port}i, %r{<main\b|main-content}i],
        css_touch: [] },
    ].freeze

    SURFACES = (
      BASE_SURFACES + BrgenVerticalSurfaces::SURFACES.map do |s|
        {
          app: "brgen",
          port_key: "brgen",
          path: s[:path],
          host: s[:host],
          label: "vertical_#{s[:label]}",
          first_screen: s[:expect_body] + [%r{skip-link|main-content|<main\b}i],
          css_touch: s[:label].to_s.start_with?("marketplace") ? [
            %w[brgen/app/assets/stylesheets/_marketplace_cards.scss deal-card],
            %w[shared/app/assets/stylesheets/_search_yep.scss \.search],
          ] : [],
        }
      end
    ).freeze

    def self.run
      new.run
    end

    def run
      @result = GateResult.new
      inventory = Inventory.new(root: ROOT).apps.to_h { |a| [a.name, a] }

      SURFACES.each do |surface|
        app = inventory[surface[:app]]
        next @result.fail("layout_geometry: unknown app #{surface[:app]}") unless app

        source_touch_checks(surface)
        live_first_screen(app, surface)
      end
      @result
    end

    private

    def source_touch_checks(surface)
      Array(surface[:css_touch]).each do |rel, needle|
        path = File.join(RAILS, rel)
        unless File.file?(path)
          @result.fail("layout_geometry: missing #{rel}")
          next
        end
        body = File.read(path)
        @result.fail("layout_geometry: #{rel} missing #{needle}") unless body.match?(Regexp.new(needle, Regexp::IGNORECASE))
      end
    end

    def live_first_screen(app, surface)
      label = [app.name, surface[:label] || surface[:path]].join("/")
      unless CrawlSupport.port_open?("127.0.0.1", app.port)
        @result.warn("layout_geometry: #{label} skipped (port #{app.port} closed)")
        return
      end

      url = "http://127.0.0.1:#{app.port}#{surface[:path]}"
      res = fetch(url, host: surface[:host])
      code = res.code.to_i
      unless code.between?(200, 399)
        @result.fail("layout_geometry: #{label} HTTP #{code}")
        return
      end
      body = res.body.to_s
      %w[Exception Routing\ Error].each do |bad|
        @result.fail("layout_geometry: #{label} saw #{bad}") if body.include?(bad.tr("\\", ""))
      end
      Array(surface[:first_screen]).each do |pat|
        @result.fail("layout_geometry first_screen: #{label} missing #{pat.inspect}") unless body.match?(pat)
      end

      # Hierarchy: at most one h1 in document source (skip auth-only shells)
      unless label.include?("messenger") || label.include?("cart")
        h1s = body.scan(/<h1\b/i).size
        @result.fail("layout_geometry hierarchy: #{label} has #{h1s} h1 (want ≤1)") if h1s > 1
        @result.warn("layout_geometry hierarchy: #{label} has no h1") if h1s.zero?
      end

      # Scan-path: marketplace search/nav before product grid
      if label.include?("marketplace") && !label.include?("cart")
        search_i = body =~ /class=["'][^"']*search|id=["']navBar/i
        grid_i = body =~ /deal-grid|deal-card/i
        if search_i && grid_i && search_i > grid_i
          @result.fail("layout_geometry scan_path: #{label} search appears after product grid")
        end
      end

      # Structural DOM surface schema (P1) — principle-tagged markers + order.
      raw_label = surface[:label].to_s
      schema_id = SCHEMA_FOR_LABEL[raw_label] ||
                  SCHEMA_FOR_LABEL[label] ||
                  SCHEMA_FOR_LABEL[label.split("/").last.to_s]
      if schema_id
        @schema_checker ||= DomSurfaceSchema.new
        @schema_checker.apply_to_result!(@result, body, schema_id)
      end
    rescue StandardError => e
      @result.fail("layout_geometry: #{label} #{e.class}: #{e.message}")
    end

    def fetch(url, host: nil)
      uri = URI(url)
      Net::HTTP.start(uri.host, uri.port, open_timeout: 8, read_timeout: 15) do |http|
        req = Net::HTTP::Get.new(uri.request_uri)
        req["Host"] = host if host
        http.request(req)
      end
    end
  end
end
