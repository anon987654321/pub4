# frozen_string_literal: true

require "yaml"

module Master
  module Fix
    # Mandatory deterministic reachability preflight for every /fix run.
    # It proves the collector's complete writable corpus reaches the pass,
    # and that a RAILS run reaches every declared app and the canonical layout suite.
    class Reachability
      def initialize(root:, bus: nil)
        @root = File.expand_path(root)
        @bus = bus
      end

      def verify!(target, files:)
        target = File.expand_path(target)
        raise "target #{target} is outside MASTER repository" unless inside_repo?(target)

        expected = FileCollector.new(root: @root, bus: @bus).collect(target)
        actual = Array(files).map { |file| File.expand_path(file) }
        missing = expected - actual
        extra = actual - expected

        raise "fix reachability gap: #{missing.size} collector file(s) never reached" if missing.any?
        raise "fix reachability mismatch: #{extra.size} file(s) outside collector scope" if extra.any?

        publish_reachability(target, expected)
        verify_rails_family! if rails_target?(target)
        true
      rescue StandardError => e
        @bus&.publish("fix_loop:reachability_failed", target:, error: e.message)
        Master::Trace::Dmesg.status("reach0", "blocked: #{e.message[0, 180]}")
        raise
      end

      private

      def publish_reachability(target, expected)
        @bus&.publish("fix_loop:reachability", target:, files: expected.size)
        Master::Trace::Dmesg.status("reach0", "#{relative(target)}: #{expected.size} writable files reached")
      end

      def verify_rails_family!
        rails = File.join(@root, "..", "RAILS")
        apps = YAML.safe_load_file(File.join(rails, "apps.yml"), aliases: false).fetch("apps")
        names = apps.keys.map(&:to_s)
        raise "RAILS apps.yml declares no apps" if names.empty?

        names.each do |name|
          path = File.join(rails, name)
          raise "RAILS app missing from filesystem: #{name}" unless File.directory?(path)

          %w[
            Gemfile
            bin/rails
            bin/ci
            config/routes.rb
            app/views/layouts/application.html.erb
            app/assets/stylesheets/application.scss
          ].each do |rel|
            full = File.join(path, rel)
            raise "RAILS app #{name} missing wired surface: #{rel}" unless File.exist?(full)
          end
        end

        shared = File.join(rails, "shared")
        raise "RAILS shared engine missing from filesystem" unless File.directory?(shared)

        layout_path = File.join(@root, "gates", "lib", "layout_suite.rb")
        auditor_path = File.join(@root, "gates", "lib", "source", "frontend_auditor.rb")
        raise "layout suite missing: #{layout_path}" unless File.file?(layout_path)
        raise "frontend auditor missing: #{auditor_path}" unless File.file?(auditor_path)

        require layout_path
        require auditor_path

        leaves = Deploy::LayoutSuiteGate::LEAVES
        broken = leaves.reject { |klass| klass.is_a?(Class) && klass.respond_to?(:run) }
        raise "layout suite wiring incomplete: #{broken.map(&:to_s).join(", ")}" if broken.any?

        auditor_apps = Deploy::FrontendAuditorGate::APPS.map(&:to_s)
        missing_apps = names - auditor_apps
        raise "frontend auditor misses Rails app(s): #{missing_apps.join(", ")}" if missing_apps.any?

        observe_layout_suite!
      end

      def observe_layout_suite!
        saved = ENV["GATE_AUTOFIX"]
        ENV["GATE_AUTOFIX"] = "0"
        result = Deploy::LayoutSuiteGate.run

        @bus&.publish(
          "fix_loop:layout_sweep",
          outcome: result.outcome,
          checks: result.checks_ran,
          failures: result.failures.size,
          warnings: result.warnings.size,
          unchecked: result.unchecked.size,
          errors: result.errors.size
        )
        Master::Trace::Dmesg.status(
          "layout0",
          "RAILS family sweep: #{result.outcome}, checks=#{result.checks_ran}, " \
          "failures=#{result.failures.size}, warnings=#{result.warnings.size}, " \
          "unchecked=#{result.unchecked.size}"
        )

        raise "layout suite gate errored: #{result.errors.first}" if result.errored?
      ensure
        saved.nil? ? ENV.delete("GATE_AUTOFIX") : ENV["GATE_AUTOFIX"] = saved
      end

      def rails_target?(target)
        rails = File.expand_path(File.join(@root, "..", "RAILS"))
        target == rails || target.start_with?(rails + File::SEPARATOR)
      end

      def inside_repo?(path)
        repo = File.expand_path(File.join(@root, ".."))
        path == repo || path.start_with?(repo + File::SEPARATOR)
      end

      def relative(path)
        path.to_s.delete_prefix("#{@root}/")
      end
    end
  end
end
