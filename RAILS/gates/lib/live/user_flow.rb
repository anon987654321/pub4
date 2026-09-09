# frozen_string_literal: true

require "yaml"
require_relative "../../../../OPENBSD/lib/deploy_inventory"
require_relative "../../../../OPENBSD/lib/gate_result"
require_relative "../../../tools/crawl_support"
require_relative "../../support/gate_autofix"
require_relative "../../support/brgen_vertical_surfaces"
require_relative "../../support/guest_flow_persona"
require_relative "../../support/dom_surface_schema"
require_relative "../../support/user_flow/design_contracts"
require_relative "../../../shared/lib/pub4/master_design"

module Deploy
  # Critical-path user flows + MASTER design/principle semantics.
  # Source checks always run. Live HTTP runs when app ports are open.
  # Master principles are mapped to concrete detectables (not vibes).
  # GATE_AUTOFIX=1 remeasures design contracts after mechanical CSS patches.
  # Guest persona probes assert Craigslist-style no-signup capabilities.
  class UserFlowGate
    include DesignContracts

    ROOT = File.expand_path("../../../..", __dir__)
    RAILS_ROOT = File.join(ROOT, "RAILS")
    MASTER = File.join(ROOT, "MASTER")
    DESIGN_RULES = File.join(MASTER, "data", "rules.yml")
    PRINCIPLE_MAP = File.join(MASTER, "data", "principle_map.yml")
    WIRING_NOTES = File.join(RAILS_ROOT, "shared", "WIRING_NOTES.md")

    # Every directory that renders a view, the three apps plus brgen's engines.
    #
    # The engine views render inside brgen and live outside brgen/app, so a
    # brgen/app/views scan never saw the 71 vertical pages — the blind spot that
    # let the sub-apps drift. Read off disk rather than listed, because a list is
    # only correct until the next engine, and the last one cost 71 pages of
    # coverage before anybody noticed.
    VIEW_PATHS = (%w[brgen/app/views amber/app/views bsdports/app/views] +
                  Dir.glob(File.join(RAILS_ROOT, "brgen/engines/*/app/views"))
                     .map { |path| path.sub("#{RAILS_ROOT}/", "") }.sort).freeze

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
      @design_rules = Pub4::MasterDesign.blocks(DESIGN_RULES)
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
      response = CrawlSupport.fetch(url, host: step[:host])
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
  end
end
