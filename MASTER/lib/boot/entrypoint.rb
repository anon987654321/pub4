# frozen_string_literal: true

require "fileutils"
require "rubygems"
require "time"
require_relative "dependency_manager"
require_relative "../trace/dmesg"
require_relative "../operator/environment"
require_relative "../operator/ruby_runner"

module Master
  module Boot
    module Entrypoint
      module_function

      SUPPORTED_RUBY_MIN = Gem::Version.new("3.3.0")
      SUPPORTED_RUBY_MAX = Gem::Version.new("4.1.0")


      def prepare!(root:, env: ENV, out: $stderr, argv: ARGV, program: $PROGRAM_NAME)
        root = File.expand_path(root)
        reexec_best_ruby!(root:, env:, out:, argv:, program:)
        manager = DependencyManager.new(root:, env:, out:)
        result = manager.ensure!
        unless result.ok
          Master::Trace::Dmesg.status("deps0", result.message, io: out)
          detail = result.output.to_s.strip
          Master::Trace::Dmesg.status("deps0", detail, io: out) unless detail.empty?
          exit 78
        end

        manager.activate_environment!
        reexec_mismatched_bundler!(root:, env:, out:, argv:, program:)
        activate_bundle!(root)
        write_boot_receipt!(root:, out:)

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
        Master::Trace::Dmesg.status("bundler0", "switching #{active} to #{lock_version}", io: out)
        exec(clean_env, File.expand_path(program), *argv)
      rescue Errno::ENOENT => e
        Master::Trace::Dmesg.status("bundler0", "cannot re-exec #{program}, #{e.message}", io: out)
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

      def reexec_best_ruby!(root:, env:, out:, argv:, program:)
        return if env["MASTER_RUBY_REEXEC_DONE"] == "1"

        candidate = Operator::RubyRunner.best_available_ruby(root:)
        return unless candidate
        return if same_file?(RbConfig.ruby, candidate[:path])

        Master::Trace::Dmesg.status(
          "ruby0",
          "switching #{RUBY_VERSION} to #{candidate[:version]} (#{candidate[:path]})",
          io: out,
        )
        clean_env = env.to_h.dup
        %w[RUBYOPT RUBYLIB].each { |key| clean_env.delete(key) }
        clean_env["MASTER_RUBY_REEXEC_DONE"] = "1"
        exec(clean_env, candidate[:path], File.expand_path(program), *argv)
      rescue ArgumentError => e
        Master::Trace::Dmesg.status("ruby0", "Ruby selection failed, #{e.message}", io: out)
        exit 78
      end

      def write_boot_receipt!(root:, out:)
        require "json"
        path = File.join(root, ".master", "boot.json")
        payload = {
          "pid" => Process.pid,
          "ruby" => RUBY_VERSION,
          "ruby_path" => RbConfig.ruby,
          "platform" => RUBY_PLATFORM,
          "bundler" => Gem.loaded_specs["bundler"]&.version&.to_s,
          "root" => root,
          "at" => Time.now.utc.iso8601,
        }
        FileUtils.mkdir_p(File.dirname(path))
        tmp = "#{path}.#{Process.pid}.tmp"
        File.write(tmp, JSON.generate(payload) + "\n", mode: "w", encoding: "UTF-8")
        File.rename(tmp, path)
      rescue StandardError => e
        Master::Trace::Dmesg.status("boot0", "receipt unavailable, #{e.class}: #{e.message}", io: out)
      ensure
        File.delete(tmp) if defined?(tmp) && tmp && File.exist?(tmp)
      end

      def same_file?(a, b)
        return File.identical?(a, b) if File.exist?(a)

        false
      rescue StandardError
        false
      end
    end
  end
end
