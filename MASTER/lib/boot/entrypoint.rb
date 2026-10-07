# frozen_string_literal: true

require "fileutils"
require "json"
require "rubygems"
require_relative "dependency_manager"
require_relative "../trace/dmesg"
require_relative "../operator/environment"

module Master
  module Boot
    module Entrypoint
      module_function

      OPENBSD_RUBY_PATTERN = /\A3\.(?:3|4)\.\d+\z/
      ANDROID_RUBY_PATTERN = /\A4\.0\.\d+\z/

      def prepare!(root:, env: ENV, out: $stderr, argv: ARGV, program: $PROGRAM_NAME)
        root = File.expand_path(root)
        reexec_pinned_ruby!(root:, env:, out:, argv:, program:)
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

      def reexec_pinned_ruby!(root:, env:, out:, argv:, program:)
        return if env["MASTER_ALLOW_UNPINNED_RUBY"] == "1"

        version_file = File.join(root, ".ruby-version")
        return unless File.file?(version_file)

        expected = File.read(version_file).strip
        return if expected.empty?

        current = Gem::Version.new(RUBY_VERSION)
        pinned = Gem::Version.new(expected)

        # A version pin alone is not enough: two installations can carry the
        # same RUBY_VERSION while their gem homes disagree (a homebrew ruby
        # beside an rbenv one, each with its own default gem dir — a system
        # thor beside bundler's vendored copy raises a superclass mismatch, and
        # native extensions linked against the other installation LoadError).
        # When the pinned rbenv binary exists, exec into it so bundle
        # resolves from one gem home under one interpreter.
        if (rbenv_root = env["RBENV_ROOT"] || File.expand_path("~/.rbenv"))
          direct = File.join(rbenv_root, "versions", expected, "bin", "ruby")
          if File.executable?(direct) && !same_file?(RbConfig.ruby, direct)
            Master::Trace::Dmesg.status(
              "ruby0", "switching #{RbConfig.ruby} to #{direct}", io: out
            )
            exec(direct, File.expand_path(program), *argv)
          end
        end

        return if current == pinned
        return if OPENBSD_RUBY_PATTERN.match?(RUBY_VERSION) && RUBY_PLATFORM.include?("openbsd")
        return if ANDROID_RUBY_PATTERN.match?(RUBY_VERSION) && RUBY_PLATFORM.include?("android")

        wrapper = File.join(root, "bin", "ruby")
        unless File.executable?(wrapper)
          Master::Trace::Dmesg.status("ruby0", "#{RUBY_VERSION}, #{expected} required, #{wrapper} unavailable", io: out)
          exit 78
        end

        # bin/ruby owns platform-specific Ruby acquisition. Passing the original
        # program and argv through it lets every executable share that logic.
        return if File.expand_path(program) == File.expand_path(wrapper)

        Master::Trace::Dmesg.status("ruby0", "switching #{RUBY_VERSION} to #{expected}", io: out)
        exec(wrapper, File.expand_path(program), *argv)
      rescue ArgumentError
        Master::Trace::Dmesg.status("ruby0", "invalid .ruby-version, #{version_file}", io: out)
        exit 78
      end

      def write_boot_receipt!(root:, out:)
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
        tmp = "#{path}.#{$}.tmp"
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
