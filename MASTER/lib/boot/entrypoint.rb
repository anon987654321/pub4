# frozen_string_literal: true

require "rubygems"
require_relative "dependency_manager"

module Master
  module Boot
    module Entrypoint
      module_function

      def prepare!(root:, env: ENV, out: $stderr, argv: ARGV, program: $PROGRAM_NAME)
        root = File.expand_path(root)
        reexec_pinned_ruby!(root:, env:, out:, argv:, program:)
        manager = DependencyManager.new(root:, env:, out:)
        result = manager.ensure!
        unless result.ok
          out.puts("deps0: #{result.message}")
          detail = result.output.to_s.strip
          out.puts(detail) unless detail.empty?
          exit 78
        end

        manager.activate_environment!
        reexec_mismatched_bundler!(root:, env:, out:, argv:, program:)
        activate_bundle!(root)
        verify_import_graph!(root:, out:)

        true
      end

      def reexec_mismatched_bundler!(root:, env:, out:, argv:, program:)
        lock_version = locked_bundler_version(root)
        return if lock_version.empty?

        active = Gem.loaded_specs["bundler"]&.version&.to_s
        return if active.nil? || active == lock_version
        return if env["MASTER_BUNDLER_REEXEC_DONE"] == "1"

        clean_env = env.to_h.dup
        %w[RUBYOPT RUBYLIB].each { |key| clean_env.delete(key) }
        %w[
          BUNDLE_APP_CONFIG BUNDLE_BIN BUNDLE_DEPLOYMENT BUNDLE_FROZEN
          BUNDLE_GEMFILE BUNDLE_IGNORE_CONFIG BUNDLE_JOBS BUNDLE_LOCKFILE
          BUNDLE_ONLY BUNDLE_PATH BUNDLE_RETRY BUNDLE_USER_CONFIG
          BUNDLE_USER_HOME BUNDLE_VERSION BUNDLE_WITH BUNDLE_WITHOUT
        ].each { |key| clean_env.delete(key) }
        clean_env["MASTER_BUNDLER_REEXEC_DONE"] = "1"
        out.puts("bundler0: switching #{active} -> #{lock_version}")
        exec(clean_env, File.expand_path(program), *argv)
      rescue Errno::ENOENT => e
        out.puts("bundler0: cannot re-exec #{program}: #{e.message}")
        exit 78
      end

      def verify_import_graph!(root:, out:)
        return if ENV["MASTER_SKIP_IMPORT_PREFLIGHT"] == "1"

        require_relative "../../tools/require_graph"
        report = Operator::RequireGraph.run(root:, trees: ["MASTER"])
        return if report["clean"]

        report["broken"].first(12).each do |row|
          out.puts("boot0: #{row["file"]}:#{row["line"]}: #{row["require_relative"]} -> #{row["target"]}")
        end
        out.puts("boot0: #{report["broken"].size} broken MASTER import(s)")
        out.puts("boot0: run MASTER/bin/ruby MASTER/tools/require_graph.rb")
        exit 78
      end

      def activate_bundle!(root)
        gemfile = File.join(root, "Gemfile")
        return unless File.file?(gemfile)

        ENV["BUNDLE_GEMFILE"] = gemfile
        version = locked_bundler_version(root)
        gem("bundler", version) unless version.empty?
        require "bundler/setup"
      end

      def locked_bundler_version(root)
        lockfile = File.join(root, "Gemfile.lock")
        return "" unless File.file?(lockfile)

        File.read(lockfile)[/^BUNDLED WITH\n\s+(.+)$/m, 1].to_s.strip
      end

      def reexec_pinned_ruby!(root:, env:, out:, argv:, program:)
        return if env["MASTER_ALLOW_UNPINNED_RUBY"] == "1"

        version_file = File.join(root, ".ruby-version")
        return unless File.file?(version_file)

        expected = File.read(version_file).strip
        return if expected.empty? || Gem::Version.new(RUBY_VERSION) == Gem::Version.new(expected)

        wrapper = File.join(root, "bin", "ruby")
        unless File.executable?(wrapper)
          out.puts("ruby0: #{RUBY_VERSION}; #{expected} required; #{wrapper} is unavailable")
          exit 78
        end

        # bin/ruby owns platform-specific Ruby acquisition. Passing the original
        # program and argv through it lets every executable share that logic.
        return if File.expand_path(program) == File.expand_path(wrapper)

        out.puts("ruby0: switching #{RUBY_VERSION} -> #{expected}")
        exec(wrapper, File.expand_path(program), *argv)
      rescue ArgumentError
        out.puts("ruby0: invalid .ruby-version in #{version_file}")
        exit 78
      end
    end
  end
end
