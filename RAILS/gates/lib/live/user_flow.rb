# frozen_string_literal: true

require "net/http"
require "uri"
require "yaml"
require_relative "../../../../OPENBSD/lib/deploy_inventory"
require_relative "../../../../OPENBSD/lib/gate_result"
require_relative "../../../tools/crawl_support"
require_relative "../../support/gate_autofix"
require_relative "../../support/brgen_vertical_surfaces"
require_relative "../../support/guest_flow_persona"
require_relative "../../support/dom_surface_schema"

module Deploy
  # Critical-path user flows + MASTER design/principle semantics.
  # Source checks always run. Live HTTP runs when app ports are open.
  # Master principles are mapped to concrete detectables (not vibes).
  # GATE_AUTOFIX=1 remeasures design contracts after mechanical CSS patches.
  # Guest persona probes assert Craigslist-style no-signup capabilities.
  class UserFlowGate
    ROOT = File.expand_path("../../../..", __dir__)
    RAILS_ROOT = File.join(ROOT, "RAILS")
    MASTER = File.join(ROOT, "MASTER")
    DESIGN_RULES = File.join(MASTER, "data", "rules.yml")
    PRINCIPLE_MAP = File.join(MASTER, "data", "principle_map.yml")
    WIRING_NOTES = File.join(RAILS_ROOT, "shared", "WIRING_NOTES.md")

    def self.run
      return run_once unless GateAutofix.enabled?

      GateAutofix.run_with_remeasure(self)
    end

    def self.run_once
      new.run_once
    end

    def run_once
      @result = GateResult.new
      load_master_context
      design_contract_checks
      inventory = Inventory.new(root: ROOT)
      inventory.apps.each do |app|
        next unless FLOW_PATHS.key?(app.name)

        source_flow_checks(app)
        live_flow_checks(app)
      end
      guest_capability_checks(inventory)
      @result
    end

    # Conceptual MASTER / RAILS design contracts → file/path detectors.
    # Each rule cites principle_map / design_rules intent.
    DESIGN_CONTRACTS = [
      {
        id: :flat_ui,
        principle: "flat_ui / rejection_of_ornament",
        meaning: "Separation via borders/surfaces, not shadows or blur",
        paths: %w[
          brgen/app/assets/stylesheets
          amber/app/assets/stylesheets
          bsdports/app/assets/stylesheets
          shared/app/assets/stylesheets
        ],
        # Intentional exceptions: yep.com pen (.search.focus box-shadow) and
        # jOxVvNE carbon-example — documented product pens. Flag elsewhere.
        forbidden: /box-shadow\s*:\s*(?!none\b)|text-shadow\s*:|backdrop-filter\s*:|filter\s*:[^;]*\bblur\(/i,
        allow_path: %r{(search_yep|jsfiddle_chrome|_marketplace_nav_bar|_marketplace_animated_logo)\.scss\z},
      },
      {
        id: :stimulus_progressive,
        principle: "stimulus_progressive / progressive_enhancement",
        meaning: "Behavior via Stimulus data-controller, not jQuery CDN apps",
        paths: %w[brgen/app/views amber/app/views bsdports/app/views],
        forbidden: /jquery(\.min)?\.js|cdn\.jsdelivr\.net\/npm\/jquery/i,
        allow_path: nil,
      },
      {
        id: :fail_visibly_payments,
        principle: "fail_fast / good_design_is_honest",
        meaning: "Checkout without keys must not pretend payment succeeded",
        paths: %w[brgen/app],
        required_any: [
          /NotConfigured|not configured|payment not configured|STRIPE_SECRET|VIPPS_.*KEY/i,
        ],
        scope_glob: "**/payments/**/*.rb",
      },
      {
        id: :skip_to_main,
        principle: "accessibility / SKIP_TO_MAIN",
        meaning: "Every app layout has skip link to #main-content",
        paths: %w[
          brgen/app/views/layouts/application.html.erb
          amber/app/views/layouts/application.html.erb
          bsdports/app/views/layouts/application.html.erb
        ],
        required_all: [/#main-content/, /skip-link|Skip to main/i],
      },
      {
        id: :single_h1_marketplace_listings,
        principle: "hierarchy / clarity",
        meaning: "Marketplace listings index exposes exactly one document h1",
        paths: %w[brgen/engines/marketplace/app/views/marketplace/listings/index.html.erb],
        required_all: [/<h1\b/i],
        max_h1: 1,
      },
      {
        id: :vertical_accent_single_map,
        principle: "consistency / design_tokens exact_token_use",
        meaning: "Vertical accents only from design_tokens / _vertical_shell",
        paths: %w[brgen/app/assets/stylesheets],
        # Local sheets must not re-assign --accent except shell
        forbidden_in: {
          glob: "_vertical_*.scss",
          pattern: /--accent\s*:/,
          allow_file: /_vertical_shell\.scss\z/,
        },
      },
      {
        id: :touch_target_buy_bar,
        principle: "fitts_law / touch target_min_px 44",
        meaning: "Sticky buy bar CTAs declare min-height 44px",
        # Was brgen/app/assets/stylesheets/_marketplace.scss, which has not held
        # the buy bar since the verticals became mountable engines — the same
        # blind spot that cost four other scanners 57 views. It also read
        # `required_any: [44px literal, listing-buy-bar]`, so a sheet merely
        # mentioning the class satisfied a rule about touch geometry, and the
        # literal no longer matches a tree that spells the floor var(--tap-min).
        # Both halves are required now, against the file that actually styles it.
        paths: %w[brgen/engines/marketplace/app/assets/stylesheets/_vertical_marketplace.scss],
        required_all: [/\.listing-buy-bar-cta/, /min-height:\s*(?:44px|var\(--tap-min\))/],
      },
    ].freeze

    FLOW_PATHS = begin
      brgen_paths = BrgenVerticalSurfaces::SURFACES.map do |s|
        {
          path: s[:path],
          host: s[:host],
          label: "vertical_#{s[:label]}",
          expect_status: (200..399),
          expect_body: s[:expect_body],
        }
      end
      brgen_paths << {
        path: "/session/new",
        host: nil,
        label: "sign_in",
        expect_status: (200..399),
        expect_body: [/Sign|Log|password|session|Vipps|Google/i],
      }
      {
        "brgen" => brgen_paths,
        "amber" => [
          { path: "/", expect_status: (200..399), expect_body: [/Amber|wardrobe|main|Signup|Login|jox|item/i], host: nil },
          { path: "/session/new", expect_status: (200..399), expect_body: [/Sign|Log|password|session/i], host: nil, label: "sign_in" },
        ],
        "bsdports" => [
          { path: "/", expect_status: (200..399), expect_body: [/port|BSD|main|BSDports/i], host: nil },
          { path: "/ports", expect_status: (200..399), expect_body: [/port|search|category/i], host: nil, label: "ports_index" },
        ],
      }
    end.freeze

    # Marketplace controllers/views live in engines/marketplace since the
    # vertical-as-engine split; only the payment services stayed in the host app.
    # These are relative to RAILS/<app>, so the engine prefix rides along here.
    MP = "engines/marketplace/app"

    SOURCE_FLOW_MARKERS = {
      "brgen" => {
        "marketplace cart" => ["#{MP}/controllers/marketplace/carts_controller.rb", "#{MP}/views/marketplace/carts/show.html.erb"],
        "marketplace nav bar" => ["#{MP}/views/marketplace/_nav_bar.html.erb"],
        "yep search surface" => %w[../shared/app/assets/stylesheets/_search_yep.scss],
        "payment scaffold or honest stub" => [
          "app/services/marketplace/payments/stripe_checkout.rb",
          "app/services/marketplace/payments/vipps_checkout.rb",
          "#{MP}/controllers/marketplace/checkouts_controller.rb",
        ],
      },
      "amber" => {
        "jox chrome" => %w[app/assets/stylesheets/_jsfiddle_chrome.scss app/views/shared/_jox_logo.html.erb],
      },
      "bsdports" => {
        "jox chrome" => %w[app/assets/stylesheets/_jsfiddle_chrome.scss app/views/shared/_jox_logo.html.erb],
      },
    }.freeze

    private

    def load_master_context
      @design_rules = ((YAML.safe_load_file(DESIGN_RULES, aliases: true) if File.file?(DESIGN_RULES)) || {})["design_rules"] || {}
      @principle_map = File.file?(PRINCIPLE_MAP) ? YAML.safe_load_file(PRINCIPLE_MAP) : {}
      unless File.file?(DESIGN_RULES)
        @result.fail("user_flow: missing MASTER/data/rules.yml")
      end
      unless File.file?(PRINCIPLE_MAP)
        @result.fail("user_flow: missing MASTER/data/principle_map.yml")
      end
      # Semantic anchors must exist so principles stay authoritative
      flat = @principle_map.dig("principles", "flat_ui") || @principle_map.dig("clusters", "aesthetic")
      @result.fail("user_flow: principle_map missing aesthetic/flat_ui cluster") unless flat
      touch = @design_rules.dig("layout_rules", "touch", "target_min_px")
      @result.fail("user_flow: design_rules layout_rules.touch.target_min_px missing") unless touch.to_i >= 44
      @result.warn("user_flow: MASTER design_rules + principle_map loaded (semantic floor)")
    end

    def design_contract_checks
      DESIGN_CONTRACTS.each { |contract| apply_design_contract(contract) }
      # WIRING_NOTES flat rule still the product constitution for non-pen CSS
      if File.file?(WIRING_NOTES)
        notes = File.read(WIRING_NOTES)
        @result.fail("user_flow: WIRING_NOTES lost Flat rule") unless notes.match?(/Flat rule|box-shadow/i)
      end
    end

    def apply_design_contract(contract)
      label = "design:#{contract[:id]} (#{contract[:principle]})"
      Array(contract[:paths]).each do |rel|
        abs = File.join(RAILS_ROOT, rel)
        unless File.exist?(abs)
          # Payment files may not exist yet — warn so flow gate still teaches the contract
          if contract[:id] == :fail_visibly_payments
            @result.warn("#{label}: payment paths not present yet — create honest NotConfigured stubs")
            next
          end
          @result.fail("#{label}: missing path #{rel}")
          next
        end

        if File.directory?(abs)
          scan_directory_contract(abs, contract, label)
        else
          scan_file_contract(abs, rel, contract, label)
        end
      end
    end

    def scan_directory_contract(dir, contract, label)
      if contract[:forbidden_in]
        spec = contract[:forbidden_in]
        Dir.glob(File.join(dir, "**", spec[:glob])).each do |path|
          next if spec[:allow_file] && path.match?(spec[:allow_file])

          body = File.read(path)
          if body.match?(spec[:pattern])
            @result.fail("#{label}: #{path.sub(RAILS_ROOT + '/', '')} reassigns vertical accent (use _vertical_shell only)")
          end
        end
      end

      if contract[:scope_glob]
        files = Dir.glob(File.join(dir, contract[:scope_glob]))
        if files.empty? && contract[:required_any]
          @result.warn("#{label}: no files match #{contract[:scope_glob]}")
          return
        end
        files.each { |path| scan_file_contract(path, path.sub(RAILS_ROOT + "/", ""), contract, label) }
        return
      end

      return unless contract[:forbidden]

      Dir.glob(File.join(dir, "**/*.{scss,css,erb,js,html}")).each do |path|
        next if contract[:allow_path] && path.match?(contract[:allow_path])

        body = File.read(path)
        if body.match?(contract[:forbidden])
          @result.fail("#{label}: forbidden pattern in #{path.sub(RAILS_ROOT + '/', '')}")
        end
      end
    end

    def scan_file_contract(path, rel, contract, label)
      body = File.read(path)
      Array(contract[:required_all]).each do |pat|
        @result.fail("#{label}: #{rel} missing #{pat.inspect}") unless body.match?(pat)
      end
      if contract[:required_any]
        unless contract[:required_any].any? { |pat| body.match?(pat) }
          @result.fail("#{label}: #{rel} missing any of #{contract[:required_any].map(&:inspect).join(', ')}")
        end
      end
      if contract[:max_h1]
        count = body.scan(/<h1\b/i).size
        @result.fail("#{label}: #{rel} has #{count} h1 tags (max #{contract[:max_h1]})") if count > contract[:max_h1]
      end
      if contract[:forbidden] && !(contract[:allow_path] && path.match?(contract[:allow_path]))
        @result.fail("#{label}: forbidden pattern in #{rel}") if body.match?(contract[:forbidden])
      end
    end

    def source_flow_checks(app)
      markers = SOURCE_FLOW_MARKERS.fetch(app.name, {})
      markers.each do |name, rels|
        present = Array(rels).any? { |rel| File.file?(File.join(RAILS_ROOT, app.name, rel)) || File.file?(File.expand_path(rel, File.join(RAILS_ROOT, app.name))) }
        # allow relative ../shared
        present ||= Array(rels).any? { |rel| File.file?(File.expand_path(rel, File.join(RAILS_ROOT, app.name))) }
        if name.include?("payment") && !present
          @result.warn("#{app.name}: source flow '#{name}' not fully wired (honest stub still required by design contract)")
        elsif !present
          @result.fail("#{app.name}: source flow missing '#{name}' (#{Array(rels).join(', ')})")
        end
      end
    end

    def live_flow_checks(app)
      unless CrawlSupport.port_open?("127.0.0.1", app.port)
        @result.skipped_live("#{app.name}: live user flows skipped; port #{app.port} closed")
        return
      end

      FLOW_PATHS.fetch(app.name).each do |step|
        run_live_step(app, step)
      end
    end

    def run_live_step(app, step)
      label = step[:label] || step[:path]
      url = "http://127.0.0.1:#{app.port}#{step[:path]}"
      response = fetch_with_host(url, host: step[:host])
      code = response.code.to_i
      range = step[:expect_status]
      ok_status = range.respond_to?(:cover?) ? range.cover?(code) : Array(range).map(&:to_i).include?(code)
      unless ok_status
        @result.fail("#{app.name}/#{label}: HTTP #{code} for #{url}#{step[:host] ? " Host=#{step[:host]}" : ""}")
        return
      end

      body = response.body.to_s.dup.force_encoding(Encoding::UTF_8)
      body = body.encode(Encoding::UTF_8, invalid: :replace, undef: :replace) unless body.valid_encoding?
      %w[Exception Routing\ Error].each do |bad|
        @result.fail("#{app.name}/#{label}: saw #{bad}") if body.include?(bad.tr("\\", ""))
      end
      Array(step[:expect_body]).each do |pat|
        @result.fail("#{app.name}/#{label}: body missing #{pat.inspect}") unless body.match?(pat)
      end

      # Guest-open surfaces must not present the hard auth wall copy.
      if body.match?(/Sign in to continue/i) && guest_open_label?(label)
        @result.fail("#{app.name}/#{label}: auth wall on guest-open surface (principle=clarity)", severity: :hard)
      end

      # Semantic HTML floor on live pages (MASTER accessibility cluster)
      if body.include?("<html")
        @result.fail("#{app.name}/#{label}: missing skip or main landmark") unless body.match?(/main-content|<main\b/i)
      end
    rescue StandardError => e
      @result.fail("#{app.name}/#{label}: #{e.class}: #{e.message}")
    end

    def guest_open_label?(label)
      label.to_s.match?(/marketplace|live|dating|messenger|core|cart|home|vertical_/i)
    end

    def guest_capability_checks(inventory)
      brgen = inventory.apps.find { |a| a.name == "brgen" }
      return unless brgen

      open = CrawlSupport.port_open?("127.0.0.1", brgen.port)
      GuestFlowPersona.new(port: brgen.port).run_brgen_probes!(@result, port_open: open)
    end

    def fetch_with_host(url, host: nil, timeout: 15)
      uri = URI(url)
      Net::HTTP.start(uri.host, uri.port, open_timeout: 8, read_timeout: timeout) do |http|
        req = Net::HTTP::Get.new(uri.request_uri)
        req["Host"] = host if host
        http.request(req)
      end
    end
  end
end
