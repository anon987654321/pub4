# frozen_string_literal: true

require "fileutils"
require_relative "sw_strategy"

module Master
  module Rails
    class MobilePwaOperator
      DEPLOY_RAILS = Master::DEPLOY_RAILS

      MODES = %i[generate_from_blank refactor_existing redesign_ui audit_pwa mine_reference_repos].freeze

      DOCTRINE = Master::Ground::Axioms::RailsDoctrine::PILLARS

      INTENT_MODE = {
        generate_rails_pwa: :generate_from_blank,
        refactor_rails_app: :refactor_existing,
        redesign_mobile_pwa: :redesign_ui,
        audit_rails_pwa: :audit_pwa,
      }.freeze

      def initialize(agent: nil, root: Master::ROOT, event_bus: nil)
        @agent = agent
        @root = root
        @bus = event_bus
        @audit = Rails8AppAudit.new(root:)
        @hotwire = HotwireRefactorPolicy.new
        @pwa = PwaAudit.new(root:)
        @design = Master::Design::MobileFirstPwaProfiles.new
        @routes_views = RoutesViewsAudit.new(root:)
        @catalog = Master::Ground::RepoMining::MobileWebClusterCatalog.new
      end

      def call(intent:, app: nil, goal: nil)
        mode = INTENT_MODE.fetch(intent.to_sym, :audit_pwa)
        app_path = resolve_app_path(app)

        @bus&.publish("rails_pwa:start", mode:, app: File.basename(app_path))

        result = case mode
                 when :audit_pwa then audit(app_path)
                 when :refactor_existing then refactor(app_path, goal:)
                 when :redesign_ui then redesign(app_path)
                 when :generate_from_blank then generate(goal:)
                 when :mine_reference_repos then mine(intent)
                 end

        @bus&.publish("rails_pwa:done", mode:, ok: result.ok?)
        result
      end

      def fix_app(app_name)
        path = resolve_app_path(app_name)
        return Result.err("unknown app: #{app_name}", category: :validation) if path == @root

        changes = [fix_offline_view(path), fix_service_worker(path, app_name)].compact
        return Result.err("no changes needed for #{app_name}", category: :validation) if changes.empty?

        Result.ok({ app: app_name, path:, changes: })
      rescue StandardError => e
        Result.err("fix_app #{app_name}: #{e.message}", category: :unknown)
      end

      OFFLINE_TEMPLATE = File.join(__dir__, "templates", "rails_pwa", "offline.html.erb").freeze

      def fix_offline_view(path)
        offline_view = File.join(path, "app", "views", "pages", "offline.html.erb")
        return if File.exist?(offline_view)

        FileUtils.mkdir_p(File.dirname(offline_view))
        File.write(offline_view, File.read(OFFLINE_TEMPLATE))
        "offline page"
      end

      def fix_service_worker(path, app_name)
        sw_path = @pwa.audit(path).fetch(:service_worker)
        return unless sw_path

        sw_source = File.read(File.join(path, sw_path))
        return unless SwStrategy.cache_first_only?(sw_source)

        shared = File.join(DEPLOY_RAILS, "shared", "pwa", "service_worker.js")
        return unless File.file?(shared)

        target = File.join(path, sw_path)
        content = File.read(shared).gsub("__APP_NAME__", app_name.to_s).gsub("__CACHE_VERSION__", "v2")
        File.write(target, content)
        "service worker"
      end

      def audit_all_deploy
        results = Rails8AppAudit.new.scan_all_deploy.map do |app_state|
          next app_state if app_state[:error]
          pwa_result = @pwa.audit(app_state[:path])
          design_result = @design.audit(app_state[:path])
          routes_result = @routes_views.audit(app_state[:path])
          {
            app: app_state[:app],
            state: app_state,
            pwa: pwa_result,
            design: design_result,
            routes: routes_result,
            verdict: verdict(pwa_result, design_result),
          }
        end
        Result.ok(results)
      end

      private

      def resolve_app_path(app)
        return @root unless app

        candidate = File.join(DEPLOY_RAILS, app.to_s)
        Dir.exist?(candidate) ? candidate : @root
      end

      def audit(app_path)
        app_state = @audit.scan(app_path)
        pwa_result = @pwa.audit(app_path)
        design_result = @design.audit(app_path)
        routes_result = @routes_views.audit(app_path)
        refs = @catalog.for_intent(:audit_rails_pwa)

        Result.ok({
          app: app_state,
          pwa: pwa_result,
          design: design_result,
          routes: routes_result,
          references: refs.map { |r| "#{r.repo} — #{r.why}" },
          verdict: verdict(pwa_result, design_result),
          plan: @hotwire.plan_for(app_state),
        })
      end

      def refactor(app_path, goal:)
        app_state = @audit.scan(app_path)
        js_source = read_js(app_path)
        erb_source = read_erb(app_path)

        js_violations = @hotwire.violations_in(js_source, type: :js)
        erb_violations = @hotwire.violations_in(erb_source, type: :erb)
        plan = @hotwire.plan_for(app_state)
        refs = @catalog.for_intent(:refactor_existing)

        Result.ok({
          app: app_state,
          js_violations:,
          erb_violations:,
          plan:,
          references: refs.map { |r| "#{r.repo} — #{r.why}" },
          goal:,
        })
      end

      def redesign(app_path)
        design_result = @design.audit(app_path)
        refs = @catalog.for_intent(:redesign_mobile_pwa)

        Result.ok({
          design: design_result,
          recommendations: @design.recommendations(design_result),
          references: refs.map { |r| "#{r.repo} — #{r.why}" },
        })
      end

      def generate(goal:)
        refs = @catalog.for_intent(:generate_rails_pwa)
        Result.ok({
          goal:,
          stack: %i[rails_8 hotwire turbo stimulus solid_queue solid_cache solid_cable importmap],
          plan: generation_plan(goal),
          references: refs.map { |r| "#{r.repo} — #{r.why}" },
        })
      end

      def mine(intent)
        entries = @catalog.for_intent(intent)
        Result.ok(entries.map { |e| { repo: e.repo, pattern: e.pattern, why: e.why, risk: e.risk } })
      end

      def verdict(pwa_result, design_result)
        critical = pwa_result[:findings].count { |f| f.severity == :critical }
        high = pwa_result[:findings].count { |f| f.severity == :high } +
               design_result[:violations].count { |v| v.is_a?(Hash) && v[:severity] == :high }
        return :red if critical.positive?
        :green
      end

      def generation_plan(goal)
        name = goal.to_s.downcase.gsub(/[^a-z0-9]/, "_").squeeze("_")
        [
          "[#{DOCTRINE[:omakase]}] rails new #{name} --skip-action-mailer --skip-action-mailbox --skip-action-text",
          "[#{DOCTRINE[:integrated]}] Solid Trifecta: bundle add solid_queue solid_cache solid_cable && bin/rails solid_queue:install solid_cache:install solid_cable:install",
          "[#{DOCTRINE[:convention]}] Propshaft: bundle add propshaft (default asset pipeline, replaces Sprockets)",
          "Generate mobile-first layout: <header>, <nav>, <main>, <footer> landmarks",
          "Add 192x192 and 512x512 icons; populate app/views/pwa/manifest.json.erb",
          "Upgrade app/views/pwa/service-worker.js: network-first for HTML, cache-first for static assets, network-only for auth routes",
          "Add prefers-reduced-motion guard to all animation/transition declarations",
          "Baseline accessibility: focus-visible, 44px touch targets, form <label> coverage",
        ]
      end

      def read_js(path)
        Dir.glob(File.join(path, "app", "javascript", "**", "*.js")).first(20)
           .map { |f| File.read(f) rescue "" }.join("\n")
      end

      def read_erb(path)
        Dir.glob(File.join(path, "app", "views", "**", "*.erb")).first(40)
           .map { |f| File.read(f) rescue "" }.join("\n")
      end
    end
  end
end
