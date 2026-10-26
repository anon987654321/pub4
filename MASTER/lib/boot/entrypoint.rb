# frozen_string_literal: true

require "fileutils"
require "rubygems"

# Ruby activates its default gems the moment a stdlib file asks for them, and
# Bundler then refuses a lockfile that pins a newer one ("already activated date
# 3.4.1, but your Gemfile requires date 3.5.1"). The lock is written for Ruby
# 4.0, where json 2.18.0 and date 3.5.1 are the defaults; vm23 runs 3.4, where
# they are older and the newer copies live only in the deploy bundle. So the
# deploy bundle joins the gem path first, and each pinned default is activated
# at its locked version before `require "time"` pulls in date. This runs at load
# time, not in prepare!, because reexec_mismatched_bundler! starts a fresh
# process that loads this file again.
boot_root = File.expand_path("../..", __dir__)
bundle_config = File.join(boot_root, ".bundle", "config")
deploy_bundle = File.file?(bundle_config) ? File.binread(bundle_config)[/^BUNDLE_PATH:\s*"?([^"\s]+)"?\s*$/, 1] : nil
if deploy_bundle
  gem_dirs = Dir.glob(File.join(deploy_bundle, "ruby", "*")).select { |dir| File.directory?(File.join(dir, "gems")) }
  unless gem_dirs.empty?
    Gem.paths = { "GEM_HOME" => Gem.paths.home, "GEM_PATH" => [*gem_dirs, *Gem.path].join(File::PATH_SEPARATOR) }
  end
end
boot_lockfile = File.join(boot_root, "Gemfile.lock")
boot_lock = File.file?(boot_lockfile) ? File.binread(boot_lockfile) : ""
%w[json date].each do |name|
  pin = boot_lock[/^    #{name} \(([\d.]+)\)$/, 1]
  next unless pin

  begin
    gem name, pin
  rescue Gem::LoadError
    nil
  end
end
require "time"

require_relative "dependency_manager"
require_relative "../trace/dmesg"
require_relative "../operator/environment"
require_relative "../operator/ruby_runner"
require_relative "../mobile/bootstrap"

module Master
  module Boot
    module Entrypoint
      module_function

      def prepare!(root:, env: ENV, out: $stderr, argv: ARGV, program: $PROGRAM_NAME)
        # Every source file and data file in pub4 is UTF-8. A non-login shell on vm23 has no
        # locale, so Ruby read files as US-ASCII and the deploy preflight's boot died on 2026-10-22
        # matching a regex against domain_registry.rb's Norwegian letters. bin/cli pinned this for
        # itself; every MASTER process boots through here.
        Encoding.default_external = Encoding::UTF_8
        root = File.expand_path(root)
        prepare_mobile!(env:, out:)
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

      # On a phone the build tools must be there before Bundler compiles a native gem,
      # so the pinned Termux packages install ahead of the dependency check.
      def prepare_mobile!(env:, out:)
        return unless Master::Mobile::Profile.new(env:).activate!

        result = Master::Mobile::Bootstrap.new(env:).ensure!
        result.messages.each { |line| Master::Trace::Dmesg.status("mobile0", line, io: out) }
        exit 78 unless result.ok
      end

      def reexec_mismatched_bundler!(root:, env:, out:, argv:, program:)
        lock_version = locked_bundler_version(root)
        return if lock_version.empty?

        active = Gem.loaded_specs["bundler"]&.version&.to_s
        return if active.nil? || active == lock_version
        return if env["MASTER_BUNDLER_REEXEC_DONE"] == "1"
        if program.to_s == "-e"
          Master::Trace::Dmesg.status("bundler0", "cannot switch Bundler for inline -e; invoke a script file", io: out)
          exit 78
        end

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
        exec(clean_env, File.expand_path(program), *argv, unsetenv_others: true)
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

        candidate = ::Operator::RubyRunner.best_available_ruby(root:)
        return unless candidate

        # Inline Ruby has no script path to re-exec. Check the interpreter version
        # before comparing executable paths: version-manager shims can point to
        # the same Ruby through different filesystem paths.
        if program.to_s == "-e"
          return if RUBY_VERSION == candidate[:version].to_s

          Master::Trace::Dmesg.status("ruby0", "cannot switch Ruby for inline -e from #{RUBY_VERSION} to #{candidate[:version]}; invoke a script file", io: out)
          exit 78
        end
        return if same_file?(RbConfig.ruby, candidate[:path])

        Master::Trace::Dmesg.status(
          "ruby0",
          "switching #{RUBY_VERSION} to #{candidate[:version]} (#{candidate[:path]})",
          io: out,
        )
        # GEM_HOME, GEM_PATH, BUNDLE_* and BUNDLER_* (BUNDLER_SETUP alone preloads
        # bundler/setup from the old store) name the store of the Ruby
        # being left; the new Ruby must derive its own, or it loads native gems
        # linked to the old libruby.
        clean_env = env.to_h.dup
        (%w[RUBYOPT RUBYLIB GEM_HOME GEM_PATH] + DependencyManager::BUNDLE_CONTEXT_KEYS).each { |key| clean_env.delete(key) }
        clean_env.delete_if { |key, _| key.start_with?("BUNDLER_") || key == "BUNDLE_BIN_PATH" }
        clean_env["MASTER_RUBY_REEXEC_DONE"] = "1"
        # exec merges env into the inherited one; only unsetenv_others drops the keys deleted above.
        exec(clean_env, candidate[:path], File.expand_path(program), *argv, unsetenv_others: true)
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
