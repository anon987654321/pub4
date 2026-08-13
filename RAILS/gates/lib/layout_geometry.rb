# frozen_string_literal: true

require "net/http"
require "uri"
require_relative "../../../OPENBSD/lib/deploy_inventory"
require_relative "../../../OPENBSD/lib/gate_result"
require_relative "../../tools/crawl_support"
require_relative "../support/brgen_vertical_surfaces"
require_relative "../support/dom_surface_schema"

module Deploy
  # First-screen contract + hierarchy + touch geometry (MASTER layout_rules / Fitts).
  class LayoutGeometryGate
    ROOT = File.expand_path("../../..", __dir__)
    RAILS = File.join(ROOT, "RAILS")

    # The touch floor, spelled either way.
    #
    # These three surfaces were reported as having no touch floor while all
    # three set one: the tree writes `min-height: var(--tap-min)` and this
    # grepped for the literal `min-height: 44px`, so the gate was measuring a
    # spelling rather than a geometry and firing on files that satisfied it.
    #
    # Accepting the token on its name alone would be the opposite mistake — a
    # sheet that had quietly dropped to 30px would pass — so TAP_MIN_PX re-reads
    # what the token resolves to and #assert_token_floor fails if it is not 44.
    TAP_MIN = 'min-height:\s*(?:44px|var\(--tap-min\))'
    TOKENS = File.join(RAILS, "shared/app/assets/stylesheets/_dialect_tokens.scss")

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
        css_touch: [["brgen/app/assets/stylesheets/_nav.scss", TAP_MIN],
                    ["brgen/app/assets/stylesheets/_marketplace.scss", TAP_MIN]] },
      { app: "amber", port_key: "amber", path: "/", host: nil,
        first_screen: [%r{skip-link|Skip to main}i, %r{main-content|<main\b}i, %r{Amber|jox|Signup|Login|wardrobe}i],
        # Was _jsfiddle_chrome.scss + "jox-buttons", which asserted only that a
        # class name appeared in a file — not that anything rendered it and not
        # that it met a target size. Nothing rendered .jox-buttons in either app.
        # Now the same shape as brgen's: a real 44px floor in a live sheet.
        css_touch: [["amber/app/assets/stylesheets/_items.scss", TAP_MIN]] },
      { app: "bsdports", port_key: "bsdports", path: "/", host: nil,
        first_screen: [%r{skip-link|Skip to main}i, %r{main-content|<main\b}i, %r{BSD|port}i],
        css_touch: [%w[bsdports/app/assets/stylesheets/application.scss --font]] },
      { app: "bsdports", port_key: "bsdports", path: "/ports", host: nil, label: "ports",
        first_screen: [%r{search|port}i, %r{<main\b|main-content}i],
        css_touch: [] },
    ].freeze

    SURFACES = (
      BASE_SURFACES + BrgenVerticalSurfaces::SURFACES.map do |s|
        # JSON API surfaces (e.g. maps /places) have no HTML landmarks.
        json_api = s[:label].to_s.match?(/maps_places|places_json/)
        landmarks = json_api ? [] : [%r{skip-link|main-content|<main\b}i]
        {
          app: "brgen",
          port_key: "brgen",
          path: s[:path],
          host: s[:host],
          label: "vertical_#{s[:label]}",
          first_screen: Array(s[:expect_body]) + landmarks,
          skip_h1: json_api || s[:label].to_s.start_with?("maps"),
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

    def utf8_body(raw)
      body = raw.to_s.dup.force_encoding(Encoding::UTF_8)
      body.valid_encoding? ? body : body.encode(Encoding::UTF_8, invalid: :replace, undef: :replace)
    end

    # What `var(--tap-min)` is worth. Run once per gate run, not per surface —
    # every css_touch needle that accepts the token leans on this one number.
    def assert_token_floor
      return if @token_floor_checked

      @token_floor_checked = true
      unless File.file?(TOKENS)
        @result.fail("layout_geometry: missing #{TOKENS} — --tap-min is unreadable, so the touch floor is unverified")
        return
      end

      declared = File.read(TOKENS)[/--tap-min:\s*([0-9]+)px/, 1]
      if declared.nil?
        @result.fail("layout_geometry: _dialect_tokens.scss declares no --tap-min — sheets spell the floor with a token that does not exist")
      elsif declared.to_i < 44
        @result.fail("layout_geometry: --tap-min is #{declared}px, below the 44px Fitts floor — every sheet spelling it var(--tap-min) is under target")
      end
    end

    def source_touch_checks(surface)
      assert_token_floor
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
        @result.skipped_live("layout_geometry: #{label} skipped (port #{app.port} closed)")
        return
      end

      url = "http://127.0.0.1:#{app.port}#{surface[:path]}"
      res = fetch(url, host: surface[:host])
      code = res.code.to_i
      unless code.between?(200, 399)
        @result.fail("layout_geometry: #{label} HTTP #{code}")
        return
      end
      body = utf8_body(res.body)
      %w[Exception Routing\ Error].each do |bad|
        @result.fail("layout_geometry: #{label} saw #{bad}") if body.include?(bad.tr("\\", ""))
      end
      Array(surface[:first_screen]).each do |pat|
        @result.fail("layout_geometry first_screen: #{label} missing #{pat.inspect}") unless body.match?(pat)
      end

      # Hierarchy: at most one h1 in document source (skip auth-only shells / JSON APIs)
      unless label.include?("messenger") || label.include?("cart") || surface[:skip_h1]
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
