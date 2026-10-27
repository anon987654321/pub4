# frozen_string_literal: true

require "yaml"
require_relative "fix_loop/file_collector"
require_relative "../boot/paths"
require_relative "work_lane"

module Master
  module Fix
    # Mandatory deterministic reachability preflight for every /fix run.
    # It proves the collector's complete writable corpus reaches the pass,
    # and that a RAILS run reaches every declared app and the canonical layout suite.
    # The layout sweep itself renders only in a lane that asks for it (WorkLane).
    class Reachability
      TOP_LEVEL_TREES = MasterPaths::TREES

      # The last layout sweep's CheckResult, for the visual lane to group; nil when none ran.
      attr_reader :layout_sweep

      def initialize(root:, bus: nil)
        @root = File.expand_path(root)
        @repo_root = repository_root(@root)
        @bus = bus
        @fleet_verified = false
      end

      # subset: the run declared a narrower scope (--blockers), so files may be fewer than the
      # collector's; never more, and never outside it.
      def verify!(target, files:, subset: false)
        target = File.expand_path(target)
        @layout_sweep = nil
        raise "target #{target} is outside MASTER repository" unless inside_repo?(target)

        expected = collected(target)
        check_scope!(expected, Array(files).map { |file| File.expand_path(file) }, subset:)

        publish_reachability(target, expected)
        verify_fleet! if top_level_target?(target) && !@fleet_verified
        true
      rescue StandardError => e
        @bus&.publish("fix_loop:reachability_failed", target:, error: e.message)
        Master::Trace::Dmesg.status("reach0", "blocked: #{e.message[0, 180]}")
        raise
      end

      # One layout sweep, kept as layout_sweep. The visual lane on a path inside RAILS has no
      # fleet check to start it, so the lane calls this itself.
      def observe_layout_suite!
        require File.join(@repo_root, "MASTER", "checks", "lib", "layout_suite.rb")
        sweep_layout_suite!
      end

      private

      def collected(target) = Master::Fix::FixLoop::FileCollector.new(root: @root, bus: @bus).collect(target)

      def check_scope!(expected, actual, subset:)
        missing = expected - actual
        extra = actual - expected
        raise "fix reachability gap: #{missing.size} collector file(s) never reached" if missing.any? && !subset
        raise "fix reachability mismatch: #{extra.size} file(s) outside collector scope" if extra.any?
      end

      def publish_reachability(target, expected)
        @bus&.publish("fix_loop:reachability", target:, files: expected.size)
        Master::Trace::Dmesg.status("reach0", "#{relative(target)}: #{expected.size} writable files reached")
      end

      def verify_fleet!
        rails = File.join(@repo_root, "RAILS")
        apps = YAML.safe_load_file(File.join(rails, "apps.yml"), aliases: false).fetch("apps")
        names = apps.keys.map(&:to_s)
        raise "RAILS apps.yml declares no apps" if names.empty?

        engine_names = names.select { |name| engine_app?(File.join(rails, name)) }
        names.each do |name|
          path = File.join(rails, name)
          raise "RAILS app missing from filesystem: #{name}" unless File.directory?(path)

          surfaces = %w[Gemfile bin/rails bin/ci config/routes.rb]
          # An app that does not mount pub4-shared (master) has no engine layout or
          # application.scss: its pages are single-file shells over public/ CSS.
          if engine_names.include?(name)
            surfaces += %w[app/views/layouts/application.html.erb app/assets/stylesheets/application.scss]
          end

          surfaces.each do |rel|
            full = File.join(path, rel)
            raise "RAILS app #{name} missing wired surface: #{rel}" unless File.exist?(full)
          end
        end

        shared = File.join(rails, "__shared")
        raise "RAILS __shared engine missing from filesystem" unless File.directory?(shared)

        layout_path = File.join(@repo_root, "MASTER", "checks", "lib", "layout_suite.rb")
        auditor_path = File.join(@repo_root, "MASTER", "checks", "lib", "source", "frontend_auditor.rb")
        raise "layout suite missing: #{layout_path}" unless File.file?(layout_path)
        raise "frontend auditor missing: #{auditor_path}" unless File.file?(auditor_path)

        require layout_path
        require auditor_path

        leaves = Deploy::LayoutSuiteCheck::LEAVES
        broken = leaves.reject { |klass| klass.is_a?(Class) && klass.respond_to?(:run) }
        raise "layout suite wiring incomplete: #{broken.map(&:to_s).join(", ")}" if broken.any?

        auditor_apps = Deploy::FrontendAuditorCheck::APPS.map(&:to_s)
        missing_apps = engine_names - auditor_apps
        raise "frontend auditor misses Rails app(s): #{missing_apps.join(", ")}" if missing_apps.any?

        if WorkLane.runs?(:layout_sweep)
          observe_layout_suite!
        else
          Master::Trace::Dmesg.status("layout0", "RAILS family sweep not run, lane=#{WorkLane.current}")
        end
        @fleet_verified = true
      end

      def engine_app?(path)
        gemfile = File.join(path, "Gemfile")
        File.file?(gemfile) && File.read(gemfile).include?('gem "pub4-shared"')
      end

      def sweep_layout_suite!
        saved = ENV["CHECK_AUTOFIX"]
        ENV["CHECK_AUTOFIX"] = "0"
        result = @layout_sweep = Deploy::LayoutSuiteCheck.run
        publish_layout_sweep(result)
        report_layout_diagnostics!(result)
        raise "layout suite check errored: #{result.errors.first}" if result.errored?

        result
      ensure
        saved.nil? ? ENV.delete("CHECK_AUTOFIX") : ENV["CHECK_AUTOFIX"] = saved
      end

      def publish_layout_sweep(result)
        counts = %i[failures warnings unchecked errors].to_h { |kind| [kind, result.public_send(kind).size] }
        @bus&.publish("fix_loop:layout_sweep", outcome: result.outcome, checks: result.checks_ran, **counts)

        detail = counts.except(:errors).map { |kind, size| "#{kind}=#{size}" }.join(", ")
        line = "RAILS family sweep: #{result.outcome}, checks=#{result.checks_ran}, #{detail}"
        Master::Trace::Dmesg.status("layout0", line)
      end

      # A count tells the operator that the sweep failed, not what to repair.
      # Keep every hard failure and unchecked precondition visible; cap only the
      # secondary warning stream, with the exact omitted count still recorded.
      def report_layout_diagnostics!(result)
        result.warnings.grep(/\Acoverage0:/).each do |line|
          Master::Trace::Dmesg.status("layout0", line)
        end

        warnings = result.warnings.reject { |line| line.start_with?("coverage0:") }
        actionable, contextual = warnings.partition do |line|
          line.match?(/\A(?:css_constitution |scale_ratchet:|design_metrics |typography_contract:|frontend_auditor:|layout_search:|visual_quality:)/)
        end
        {
          "failure" => [result.failures, 100],
          "unchecked" => [result.unchecked, 40],
          "error" => [result.errors, 40],
          "diagnostic" => [actionable, 100],
          "warning" => [contextual, 24],
        }.each do |kind, (rows, limit)|
          rows.first(limit).each do |line|
            Master::Trace::Dmesg.status("layout0", "#{kind}: #{line.to_s[0, 500]}")
          end
          omitted = rows.size - limit
          Master::Trace::Dmesg.status("layout0", "#{kind}: #{omitted} additional item(s) omitted") if omitted.positive?
        end
      end

      # The whole tree, not a path inside it: the fleet check and the layout browser sweep it
      # starts cost minutes and say nothing about one Ruby file.
      def top_level_target?(target)
        TOP_LEVEL_TREES.any? { |name| target == File.join(@repo_root, name) }
      end

      def inside_repo?(path)
        path == @repo_root || path.start_with?(@repo_root + File::SEPARATOR)
      end

      def repository_root(root)
        return Master::REPO_ROOT if defined?(Master::REPO_ROOT) && root == Master::ROOT
        return root if File.directory?(File.join(root, "MASTER"))

        File.expand_path("..", root)
      end

      def relative(path)
        path.to_s.delete_prefix("#{@root}/")
      end
    end
  end
end
