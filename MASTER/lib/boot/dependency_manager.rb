# frozen_string_literal: true

require "digest"
require "fileutils"
require "rbconfig"
require "rubygems"
require_relative "../trace/dmesg"

module Master
  module Boot
    # Repairs the runtime environment before an entrypoint loads application code.
    #
    # The order matters:
    # 1. use the Ruby that launched MASTER;
    # 2. install the Bundler version recorded by Gemfile.lock when absent;
    # 3. ask Bundler whether the locked graph is installed;
    # 4. install the smallest OS build tool set only after a native build failure;
    # 5. retry once, then report the real command and output.
    #
    # Nothing here updates a lockfile on a healthy bundle. Dependency changes remain
    # an explicit Bundler operation, not a surprise hidden inside boot.
    class DependencyManager
      SYSTEM_PACKAGES = {
        termux: %w[git clang make cmake pkg-config sqlite openssl libffi],
        openbsd: %w[pkgconf gmake sqlite3 libffi],
        macos: %w[pkg-config openssl@3 libyaml libffi sqlite],
        debian: %w[build-essential pkg-config libssl-dev libyaml-dev libffi-dev libsqlite3-dev],
        fedora: %w[gcc gcc-c++ make cmake pkgconf-pkg-config openssl-devel libyaml-devel libffi-devel sqlite-devel],
        arch: %w[base-devel cmake pkgconf openssl libyaml libffi sqlite],
      }.freeze

      BUNDLE_CONTEXT_KEYS = %w[
        BUNDLE_APP_CONFIG
        BUNDLE_BIN
        BUNDLE_DEPLOYMENT
        BUNDLE_FROZEN
        BUNDLE_GEMFILE
        BUNDLE_IGNORE_CONFIG
        BUNDLE_JOBS
        BUNDLE_LOCKFILE
        BUNDLE_ONLY
        BUNDLE_PATH
        BUNDLE_RETRY
        BUNDLE_USER_CONFIG
        BUNDLE_DISABLE_SHARED_GEMS
        BUNDLE_USER_HOME
        BUNDLE_VERSION
        BUNDLE_WITH
        BUNDLE_WITHOUT
      ].freeze

      DEPENDENCY_CONFLICT = /could not find compatible versions|conflicting dependencies|incompatible requirements/i.freeze

      NATIVE_FAILURE = /
        extconf\ failed|
        cannot\ find|
        no\ such\ file|file\ not\ found|
        fatal\ error|
        failed\ to\ build\ gem|
        native\ extension|
        make:\s.*not\ found|
        pkg-config|
        permission\ denied|
        not\ writable|
        linked\ to\ incompatible|
        incompatible\ architecture|
        EACCES
      /ix.freeze

      LOCK_WAIT_SECONDS = 60
      CAPTURE_DEADLINE_SECONDS = 900
      CAPTURE_POLL_SECONDS = 0.25
      CAPTURE_DRAIN_SECONDS = 1.0

      Result = Data.define(
        :ok,
        :changed,
        :bundler,
        :bundle,
        :system,
        :message,
        :output,
      ) do
        def success? = ok
      end

      def self.ensure!(root:, env: ENV, out: $stderr, **options)
        new(root:, env:, out:, **options).ensure!
      end

      def self.install!(root:, env: ENV, out: $stderr, **options)
        new(root:, env:, out:, **options).install!
      end

      def self.system!(root:, env: ENV, out: $stderr, **options)
        new(root:, env:, out:, **options).install_system_packages!
      end

      def initialize(
        root:,
        env: ENV,
        out: $stderr,
        runner: nil,
        command_path: nil,
        home: nil
      )
        @root = File.expand_path(root)
        @env = env
        @out = out
        @runner = runner || method(:capture)
        @command_path = command_path || method(:which)
        @home = home || File.expand_path("~")
      end

      def ensure!
        return Result.new(ok: true, changed: false, bundler: nil, bundle: nil, system: nil,
                          message: "auto-install disabled", output: nil) unless enabled?
        return Result.new(ok: true, changed: false, bundler: nil, bundle: nil, system: nil,
                          message: "no Gemfile", output: nil) unless gemfile?

        deployed = adopt_deploy_bundle
        return deployed if deployed && !deployed.ok

        activate_environment!
        return deployed if deployed

        with_lock do
          bundler = ensure_bundler
          return bundler unless bundler.ok

          bundle = ensure_bundle
          return bundle if bundle.ok

          return bundle unless system_recovery_failure?(bundle)

          system = install_system_packages
          return bundle unless system[:ok]

          retry_bundle = ensure_bundle
          Result.new(
            ok: retry_bundle.ok,
            changed: bundler.changed || system[:changed] || retry_bundle.changed,
            bundler: bundler.bundler,
            bundle: retry_bundle.bundle,
            system:,
            message: retry_bundle.message,
            output: retry_bundle.output,
          )
        end
      rescue StandardError => e
        report("dependency bootstrap failed: #{e.class}: #{e.message}")
        Result.new(ok: false, changed: false, bundler: nil, bundle: nil, system: nil,
                   message: e.message, output: e.full_message)
      end

      def update!(*gems)
        return ok_result("no Gemfile", changed: false) unless gemfile?

        with_lock do
          bundler = ensure_bundler
          return bundler unless bundler.ok

          args = ["update", *gems]
          report("updating bundle#{gems.empty? ? "" : " #{gems.join(" ")}"}")
          ok, stdout, stderr = run_bundle(*args)
          output = join_output(stdout, stderr)
          if !ok && native_build_failure?(output)
            system = install_system_packages
            return fail_result("bundle update failed; system dependencies unavailable", output:) unless system[:ok]

            ok, stdout, stderr = run_bundle(*args)
            output = join_output(output, join_output(stdout, stderr))
          end

          if ok
            ok_result("bundle updated", changed: true, bundle: true, output:, bundler: bundler.bundler)
          else
            fail_result("bundle update failed", output:)
          end
        end
      rescue StandardError => e
        report("bundle update failed: #{e.class}: #{e.message}")
        Result.new(ok: false, changed: false, bundler: nil, bundle: nil, system: nil,
                   message: e.message, output: e.full_message)
      end

      def install!
        return ok_result("no Gemfile", changed: false) unless gemfile?

        with_lock do
          bundler = ensure_bundler
          return bundler unless bundler.ok

          bundle = install_bundle
          if !bundle.ok && native_build_failure?(bundle.output)
            system = install_system_packages
            return bundle unless system[:ok]

            bundle = install_bundle
          end

          Result.new(
            ok: bundle.ok,
            changed: bundler.changed || bundle.changed,
            bundler: bundler.bundler,
            bundle: bundle.bundle,
            system: nil,
            message: bundle.message,
            output: bundle.output,
          )
        end
      rescue StandardError => e
        report("dependency install failed: #{e.class}: #{e.message}")
        Result.new(ok: false, changed: false, bundler: nil, bundle: nil, system: nil,
                   message: e.message, output: e.full_message)
      end

      def install_system_packages!
        with_lock { install_system_packages }
      rescue StandardError => e
        report("system dependency install failed: #{e.class}: #{e.message}")
        { ok: false, changed: false, command: nil, output: e.full_message }
      end

      # Apply the same sanitized Bundler context used by ensure!/install! to the
      # current process before requiring bundler/setup. Without this, a standalone
      # bin/cli can validate one bundle context and activate another, producing the
      # misleading "git source is not yet checked out" error after a successful install.
      def activate_environment!
        bundle_env.each do |key, value|
          if value.nil?
            @env.delete(key)
          else
            @env[key] = value
          end
        end
        refresh_gem_state! if @env.equal?(ENV)
        true
      end

      def status
        bundler_version = locked_bundler_version
        bundle_ok, bundle_output, = run_bundle("check")
        {
          ruby: RUBY_VERSION,
          ruby_required: locked_ruby_version,
          bundler: bundler_version,
          bundler_installed: bundler_path(bundler_version),
          bundle_ok:,
          bundle_output:,
          package_manager: package_manager_name,
        }
      end

      private

      def enabled?
        @env.fetch("MASTER_AUTO_INSTALL", "1") != "0" &&
          @env.fetch("MASTER_AUTO_BUNDLE", "1") != "0"
      end

      def gemfile?
        File.file?(File.join(@root, "Gemfile"))
      end

      def locked_bundler_version
        lock = File.join(@root, "Gemfile.lock")
        return "" unless File.file?(lock)

        File.read(lock)[/^BUNDLED WITH\n\s+(.+)$/m, 1].to_s.strip
      end

      def locked_ruby_version
        lock = File.join(@root, "Gemfile.lock")
        return "" unless File.file?(lock)

        File.read(lock)[/^RUBY VERSION\n\s+ruby\s+(.+)$/m, 1].to_s.strip
      end

      # The bundle the deploy installed. vps_deploy_master.sh runs `bundle install`
      # as the deploy user with the path recorded in MASTER/.bundle/config, and
      # the daemon runs as another user whose HOME holds no private store: asking
      # it to build one means a 177-gem install under a probe timeout, with the
      # real bundle sitting next door. A bundle that already satisfies the lock
      # is read as it stands (frozen, no install, no lock write); one that does
      # not is refused loudly when this user cannot write it, and left to the
      # private store when it can, which is the behaviour before the deploy
      # bundle existed.
      def adopt_deploy_bundle
        path = deploy_bundle_path
        return unless path

        @deploy_bundle = path
        ok, stdout, stderr = run_bundle("check")
        output = join_output(stdout, stderr)
        native_ok, native_stdout, native_stderr = ok ? probe_native_bundle : [true, "", ""]
        return ok_result("deploy bundle clean", changed: false, bundle: true, output:) if ok && native_ok

        output = join_output(output, native_stdout, native_stderr)
        unless File.writable?(path)
          return fail_result(
            "deploy bundle at #{path} does not satisfy #{File.join(@root, 'Gemfile.lock')} " \
            "and uid #{Process.uid} cannot write it; run vps-deploy as the deploy user",
            output:,
          )
        end

        @deploy_bundle = nil
        nil
      end

      def deploy_bundle_path
        config = File.join(@root, ".bundle", "config")
        return unless File.file?(config)

        path = File.read(config)[/^BUNDLE_PATH:\s*"?([^"\s]+)"?\s*$/, 1]
        path if path && File.directory?(path)
      rescue SystemCallError
        nil
      end

      def ensure_bundler
        version = locked_bundler_version
        return ok_result("no Bundler pin", changed: false) if version.empty?
        return ok_result("bundler #{version} already installed", changed: false, bundler: version) if bundler_path(version)

        report("installing bundler #{version}")
        gem = gem_command
        return fail_result("gem executable missing; install RubyGems or use MASTER/bin/ruby") unless gem

        install_dir = bundler_gem_home
        ok, stdout, stderr = run(
          [gem, "install", "bundler", "-v", version, "--no-document", "--install-dir", install_dir],
          chdir: @root,
          env: bundle_env,
        )
        output = join_output(stdout, stderr)
        unless ok
          return fail_result(
            "bundler #{version} installation failed",
            output:,
          )
        end

        refresh_gem_state!
        if bundler_path(version)
          ok_result("bundler #{version} installed", changed: true, bundler: version, output:)
        else
          fail_result("bundler #{version} installed but its executable is unavailable",
                      output:)
        end
      end

      def ensure_bundle
        ok, stdout, stderr = run_bundle("check")
        output = join_output(stdout, stderr)
        return install_bundle unless ok

        native_ok, native_stdout, native_stderr = probe_native_bundle
        native_output = join_output(native_stdout, native_stderr)
        if native_ok
          return ok_result(
            "bundle clean",
            changed: false,
            bundle: true,
            output: join_output(output, native_output),
          )
        end

        unless native_build_failure?(native_output)
          return fail_result("bundle native probe failed", output: join_output(output, native_output))
        end
        unless native_output.match?(ABI_STALE_LINE) || @env["MASTER_DEPS_DISCARD_BUNDLE"] == "1"
          return fail_result(
            "bundle native probe failed (no ABI-stale evidence; gem store left intact)",
            output: join_output(output, native_output),
          )
        end

        report("rebuilding native bundle extensions")
        return fail_result("stale native bundle cleanup failed") unless discard_stale_native_bundle!
        repair_ok, repair_stdout, repair_stderr = run_bundle(
          "install", "--jobs", bundle_jobs.to_s, "--retry", "3"
        )
        repair_output = join_output(repair_stdout, repair_stderr)
        unless repair_ok
          return fail_result(
            "bundle native extension repair failed",
            output: join_output(output, native_output, repair_output),
          )
        end

        repaired_ok, repaired_stdout, repaired_stderr = probe_native_bundle
        repaired_output = join_output(repaired_stdout, repaired_stderr)
        return ok_result(
          "bundle native extensions repaired",
          changed: true,
          bundle: true,
          output: join_output(output, native_output, repair_output, repaired_output),
        ) if repaired_ok

        fail_result(
          "bundle native extension repair failed",
          output: join_output(output, native_output, repair_output, repaired_output),
        )
      end

      def probe_native_bundle
        @runner.call(
          [RbConfig.ruby, "-rbundler/setup", "-rjson", "-e", "exit"],
          chdir: @root,
          env: bundle_env,
        )
      end

      def install_bundle
        report("installing bundle for #{File.basename(@root)}")
        ok, stdout, stderr = run_bundle("install",
                                        "--jobs", bundle_jobs.to_s,
                                        "--retry", "3")
        output = join_output(stdout, stderr)
        if ok
          native_ok, native_stdout, native_stderr = probe_native_bundle
          native_output = join_output(native_stdout, native_stderr)
          return ok_result(
            "bundle installed",
            changed: true,
            bundle: true,
            output: join_output(output, native_output),
          ) if native_ok

          unless native_build_failure?(native_output)
            return fail_result("bundle native probe failed",
                               output: join_output(output, native_output))
          end

          repair_native_bundle(join_output(output, native_output))
        elsif native_build_failure?(output)
          repair_native_bundle(output)
        elsif permission_failure?(output)
          install_to_user_path(output)
        else
          message = dependency_conflict?(output) ?
            "bundle dependency constraints conflict; no automatic lockfile rewrite was attempted" :
            "bundle install failed"
          fail_result(message, output:)
        end
      end

      def repair_native_bundle(previous_output)
        unless previous_output.to_s.match?(ABI_STALE_LINE) || @env["MASTER_DEPS_DISCARD_BUNDLE"] == "1"
          return fail_result(NATIVE_REPAIR_REFUSED, output: previous_output)
        end

        report("rebuilding native bundle extensions")
        return fail_result(
          "stale native bundle cleanup failed",
          output: previous_output,
        ) unless discard_stale_native_bundle!

        repair_ok, repair_stdout, repair_stderr = run_bundle(
          "install", "--jobs", bundle_jobs.to_s, "--retry", "3"
        )
        repair_output = join_output(repair_stdout, repair_stderr)
        unless repair_ok
          return fail_result(
            "bundle native extension repair failed",
            output: join_output(previous_output, repair_output),
          )
        end

        repaired_ok, repaired_stdout, repaired_stderr = probe_native_bundle
        repaired_output = join_output(repaired_stdout, repaired_stderr)
        return ok_result(
          "bundle native extensions repaired",
          changed: true,
          bundle: true,
          output: join_output(previous_output, repair_output, repaired_output),
        ) if repaired_ok

        fail_result(
          "bundle native extension repair failed",
          output: join_output(previous_output, repair_output, repaired_output),
        )
      end

      def install_to_user_path(previous_output)
        path = File.join(@home, ".local", "share", "master", "bundles", bundle_key)
        report("bundle path is not writable; using #{path}")
        ok, stdout, stderr = run_bundle_config("path", path)
        unless ok
          return fail_result("could not set user bundle path",
                             output: join_output(previous_output, stdout, stderr))
        end

        ok, stdout, stderr = run_bundle("install", "--jobs", bundle_jobs.to_s, "--retry", "3")
        output = join_output(previous_output, stdout, stderr)
        if ok
          ok_result("bundle installed in user path", changed: true, bundle: true, output:)
        else
          message = dependency_conflict?(output) ?
            "bundle dependency constraints conflict; no automatic lockfile rewrite was attempted" :
            "bundle install failed in user path"
          fail_result(message, output:)
        end
      end

      def run_bundle(*args)
        bundle = bundler_path(locked_bundler_version) || @command_path.call("bundle")
        return [false, "", "bundle executable not found"] unless bundle

        @runner.call(
          [bundle, *args],
          chdir: @root,
          env: bundle_env,
        )
      end

      def run_bundle_config(key, value)
        bundle = bundler_path(locked_bundler_version) || @command_path.call("bundle")
        return [false, "", "bundle executable not found"] unless bundle

        @runner.call(
          [bundle, "config", "set", "--local", key, value],
          chdir: @root,
          env: bundle_env,
        )
      end

      def bundler_path(version)
        return if version.to_s.empty?

        bundler_spec(version)&.then do |spec|
          executable = File.join(spec.full_gem_path, "exe", "bundle")
          executable if File.executable?(executable)
        end
      rescue Gem::Exception
        nil
      end

      def bundler_spec(version)
        candidates = []

        path = File.join(
          bundler_gem_home,
          "specifications",
          "bundler-#{version}.gemspec",
        )
        candidates << Gem::Specification.load(path) if File.file?(path)

        candidates.concat(
          Gem::Specification.find_all_by_name("bundler").select do |spec|
            spec.version.to_s == version.to_s
          end,
        )

        candidates.compact.find do |spec|
          File.executable?(File.join(spec.full_gem_path, "exe", "bundle"))
        end
      rescue Gem::Exception
        nil
      end

      def refresh_gem_state!
        Gem.clear_paths
        if @env.equal?(ENV)
          gem_home = @env["GEM_HOME"].to_s
          gem_path = @env["GEM_PATH"].to_s.split(File::PATH_SEPARATOR).reject(&:empty?)
          Gem.use_paths(gem_home, gem_path) unless gem_home.empty?
        end
        Gem::Specification.reset
      end

      def gem_command
        candidate = File.join(RbConfig::CONFIG.fetch("bindir"), Gem.default_exec_format.sub("@", "gem"))
        return candidate if File.executable?(candidate)

        @command_path.call("gem")
      end

      def bundle_env
        bundle_gem_home = File.join(bundle_config_root, "gems")
        default_gem_path = Gem.default_dir
        ruby_bin = File.dirname(RbConfig.ruby)
        env = {
          # Bundler's executable is a Ruby shebang. Put the exact interpreter
          # that launched MASTER first so native gem builds cannot silently
          # switch to another Ruby installation with the same version.
          "PATH" => [
            ruby_bin,
            File.join(bundle_gem_home, "bin"),
            File.join(bundler_gem_home, "bin"),
            @env.fetch("PATH", ""),
          ].reject(&:empty?).join(File::PATH_SEPARATOR),
          "RUBY" => RbConfig.ruby,
          "GEM_HOME" => bundle_gem_home,
          "GEM_PATH" => [bundle_gem_home, bundler_gem_home, default_gem_path].uniq.join(File::PATH_SEPARATOR),
        }

        # A user's global ~/.bundle/config, deployment variables, or a stale
        # BUNDLE_PATH can silently change what boot installs or loads. MASTER
        # owns its dependency context, while still allowing explicit credential
        # and build variables outside this list to flow through.
        # A parent that ran bundler/setup leaves RUBYOPT and RUBYLIB pointing at
        # its own Bundler; the pinned `bundle` then loads a second copy beside it
        # and Bundler::Thor dies with a superclass mismatch.
        (BUNDLE_CONTEXT_KEYS + %w[RUBYOPT RUBYLIB BUNDLE_BIN_PATH BUNDLER_SETUP BUNDLER_VERSION]).each { |key| env[key] = nil }
        env.merge!(
          "BUNDLE_GEMFILE" => File.join(@root, "Gemfile"),
          "BUNDLE_RETRY" => "3",
          "BUNDLE_JOBS" => bundle_jobs.to_s,
          "BUNDLE_APP_CONFIG" => File.join(bundle_config_root, "app"),
          "BUNDLE_USER_CONFIG" => File.join(bundle_config_root, "global"),
          "BUNDLE_PATH" => bundle_gems_path,
          "BUNDLE_DISABLE_SHARED_GEMS" => "1",
          "BUNDLE_FROZEN" => "true",
        )
        without = @env["BUNDLE_WITHOUT"].to_s
        without = "tts" if without.empty? && @env["MASTER_SKIP_TTS"] == "1"
        env["BUNDLE_WITHOUT"] = without unless without.empty?
        deploy_bundle_env(env)
      end

      # The deploy bundle is installed without the development and test groups
      # and is only ever read.
      def deploy_bundle_env(env)
        return env unless @deploy_bundle

        env.merge!(
          "BUNDLE_PATH" => @deploy_bundle,
          "BUNDLE_FROZEN" => "true",
          "BUNDLE_APP_CONFIG" => nil,
          "GEM_HOME" => nil,
          "GEM_PATH" => nil,
        )
        env["BUNDLE_WITHOUT"] ||= "development:test"
        env
      end

      def bundle_config_root
        File.join(
          @home,
          ".master",
          "bundler",
          Digest::SHA256.hexdigest([dependency_store_root, ruby_identity].join("\0"))[0, 16],
        )
      end

      # Worktrees of one Git checkout share the immutable dependency store. The
      # checkout path itself must not create another copy of every gem.
      def dependency_store_root
        common_dir = git_common_dir
        return common_dir if common_dir

        @root
      end

      def git_common_dir
        output = IO.popen(["git", "-C", @root, "rev-parse", "--git-common-dir"], err: File::NULL, &:read)
        return unless $?.success?

        # Resolved, because git reports /private/var for a linked worktree and
        # /var for the main checkout when the system temp directory is a symlink.
        File.realpath(File.expand_path(output.strip, @root))
      rescue StandardError
        nil
      end

      # Native gems are ABI-bound to the Ruby installation that built them.
      # The Ruby version alone is not enough on macOS: Homebrew Ruby and an
      # rbenv Ruby can expose the same version while linking different libruby
      # paths. Keep their private Bundler stores separate.
      def ruby_identity
        ruby = File.realpath(RbConfig.ruby)
        prefix = RbConfig::CONFIG.fetch("prefix", "")
        library = RbConfig::CONFIG.fetch("LIBRUBY_SO", "")
        [ruby, prefix, library, RbConfig::CONFIG.fetch("ruby_version", RUBY_VERSION), RUBY_PLATFORM].join("\0")
      rescue StandardError
        [RbConfig.ruby, RbConfig::CONFIG.fetch("ruby_version", RUBY_VERSION), RUBY_PLATFORM].join("\0")
      end

      def discard_stale_native_bundle!
        path = bundle_gems_path
        return true unless File.directory?(path)

        trash = "#{path}.stale-#{Process.pid}-#{Time.now.to_i}"
        suffix = 0
        while File.exist?(trash)
          suffix += 1
          trash = "#{path}.stale-#{Process.pid}-#{Time.now.to_i}-#{suffix}"
        end
        report("moving stale native bundle #{path} to #{trash}")
        File.rename(path, trash)
        true
      rescue StandardError => e
        report("stale native bundle cleanup failed: #{e.class}: #{e.message}")
        false
      end

      def bundle_gems_path
        File.join(bundle_config_root, "gems")
      end

      def bundler_gem_home
        File.join(bundle_config_root, "bundler")
      end

      def bundle_jobs
        @env["MASTER_LOW_RESOURCE"] == "1" ? 2 : 4
      end

      # An ABI-stale bundle is moved aside and reinstalled; only a toolchain or
      # header failure that survives that rebuild needs OS packages. A header
      # failure with no ABI-stale line keeps its store and goes to OS packages directly.
      NATIVE_REPAIR_REFUSED = "native bundle repair refused (no ABI-stale evidence; gem store left intact)"

      SYSTEM_RECOVERY_MESSAGES = [
        "bundle install failed",
        "bundle install failed in user path",
        "bundle native extension repair failed",
        NATIVE_REPAIR_REFUSED,
      ].freeze
      ABI_STALE_LINE = /linked\ to\ incompatible|incompatible\ architecture/i.freeze

      def system_recovery_failure?(result)
        return false unless SYSTEM_RECOVERY_MESSAGES.include?(result.message)

        toolchain = result.output.to_s.lines.reject { |line| line.match?(ABI_STALE_LINE) }
        native_build_failure?(toolchain.join)
      end

      def dependency_conflict?(output) = output.to_s.match?(DEPENDENCY_CONFLICT)

      def native_build_failure?(output) = output.to_s.match?(NATIVE_FAILURE)

      def permission_failure?(output) = output.to_s.match?(/permission denied|not writable|EACCES/i)

      def bundle_key
        [RbConfig::CONFIG.fetch("ruby_version", RUBY_VERSION), RUBY_PLATFORM].join("-")
      end

      def install_system_packages
        specs = package_commands
        return { ok: false, changed: false, command: nil, output: "no supported package manager found" } if specs.empty?

        outputs = []
        specs.each do |argv, label|
          report("installing system build dependencies via #{label}")
          ok, stdout, stderr = @runner.call(argv, chdir: @root, env: @env.to_h)
          outputs << join_output(stdout, stderr)
          next if ok

          return { ok: false, changed: false, command: argv, output: outputs.reject(&:empty?).join("\n") }
        end

        { ok: true, changed: true, command: specs.map(&:first), output: outputs.reject(&:empty?).join("\n") }
      end

      # Compatibility helper for callers and tests that need one representative
      # package command. Installation uses package_commands so multi-step package
      # managers cannot silently discard their prerequisite step.
      def package_command = package_commands.first

      def package_commands
        packages = SYSTEM_PACKAGES.fetch(package_manager_name, [])
        return [] if packages.empty?

        case package_manager_name
        when :termux
          [[["pkg", "install", "-y", *packages], "pkg"]]
        when :openbsd
          [privileged(["pkg_add", "-I", *packages], "pkg_add")].compact
        when :macos
          [[["brew", "install", *packages], "brew"]]
        when :debian
          [
            privileged(%w[apt-get update], "apt-get"),
            privileged(["apt-get", "install", "-y", *packages], "apt-get"),
          ].compact
        when :fedora
          [privileged(["dnf", "install", "-y", *packages], "dnf")].compact
        when :arch
          [privileged(["pacman", "-Sy", "--needed", "--noconfirm", *packages], "pacman")].compact
        else
          []
        end
      end

      def privileged(command, label)
        return [command, label] if root?
        return [["doas", "-n", *command], "#{label} via doas"] if @command_path.call("doas")
        return [["sudo", "-n", *command], "#{label} via sudo"] if @command_path.call("sudo")
        nil
      end

      def root? = Process.uid.zero?

      def package_manager_name
        return :termux if @env["PREFIX"].to_s.start_with?("/data/data/com.termux/") && @command_path.call("pkg")
        return :openbsd if RUBY_PLATFORM.include?("openbsd") && @command_path.call("pkg_add")
        return :macos if RUBY_PLATFORM.include?("darwin") && @command_path.call("brew")
        return :debian if @command_path.call("apt-get")
        return :fedora if @command_path.call("dnf")
        :arch if @command_path.call("pacman")
      end

      def with_lock(wait_seconds: LOCK_WAIT_SECONDS)
        lock_path = File.join(@home, ".master", "dependency.lock")
        FileUtils.mkdir_p(File.dirname(lock_path), mode: 0o700)
        File.open(lock_path, File::RDWR | File::CREAT, 0o600) do |lock|
          deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + wait_seconds.to_f
          until lock.flock(File::LOCK_EX | File::LOCK_NB)
            if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline
              raise "dependency lock held elsewhere over #{wait_seconds}s: #{lock_path}"
            end
            sleep 0.05
          end
          yield
        end
      end

      # Runs before Bundler activation, so this uses only spawn, pipes and
      # monotonic clock primitives. A stopped package manager must not wedge boot.
      def capture(argv, chdir:, env:, deadline_seconds: CAPTURE_DEADLINE_SECONDS)
        stdout_r, stdout_w = IO.pipe
        stderr_r, stderr_w = IO.pipe
        pid = Process.spawn(env, *argv, chdir:, out: stdout_w, err: stderr_w, pgroup: true)
        stdout_w.close
        stderr_w.close
        stdout_thread = Thread.new { stdout_r.read rescue "" }
        stderr_thread = Thread.new { stderr_r.read rescue "" }
        deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + [deadline_seconds.to_f, 0.01].max
        killed = false
        status = nil

        loop do
          pair = Process.waitpid2(pid, Process::WNOHANG)
          if pair
            status = pair.last
            break
          end
          remaining = deadline - Process.clock_gettime(Process::CLOCK_MONOTONIC)
          if remaining <= 0
            kill_capture_group(pid)
            _waited, status = Process.waitpid2(pid, 0)
            killed = true
            break
          end
          sleep [CAPTURE_POLL_SECONDS, remaining].min
        end

        # A successful parent can leave a grandchild holding an inherited pipe.
        # Bound draining even after the parent timed out; never call Thread#value
        # on a reader that could still be waiting for an escaped descendant.
        drained = !killed &&
          stdout_thread.join(CAPTURE_DRAIN_SECONDS) &&
          stderr_thread.join(CAPTURE_DRAIN_SECONDS)
        unless drained
          kill_capture_group(pid)
          killed = true
          [stdout_r, stderr_r].each { |io| io.close unless io.closed? }
          [stdout_thread, stderr_thread].each do |thread|
            thread.kill if thread.alive?
            thread.join(0.1)
          end
        end

        stdout = stdout_thread.alive? ? "" : stdout_thread.value.to_s
        stderr = stderr_thread.alive? ? "" : stderr_thread.value.to_s
        stderr = join_output(stderr, "#{argv.first} process group killed after #{deadline_seconds}s deadline") if killed
        [!killed && status&.success? == true, stdout, stderr]
      ensure
        [stdout_r, stdout_w, stderr_r, stderr_w].compact.each do |io|
          io.close unless io.closed?
        end
      end

      def kill_capture_group(pid)
        Process.kill("TERM", -pid)
        sleep 0.2
        Process.kill("KILL", -pid)
      rescue Errno::ESRCH, Errno::EPERM
        nil
      end

      # Not Io::Exec.which: Exec loads Swallow, which loads json, and this runs
      # before Bundler activates the locked graph (test_helper.rb needs that
      # order). The one PATH lookup that must stay standalone.
      def which(name) = @env.fetch("PATH", "").split(File::PATH_SEPARATOR).lazy.map do |dir|
        path = File.join(dir, name)
        path if File.file?(path) && File.executable?(path)
      end.find(&:itself)

      def run(command, chdir:, env:)
        @runner.call(command, chdir:, env:)
      end

      def ok_result(message, changed:, bundler: nil, bundle: nil, output: nil)
        Result.new(ok: true, changed:, bundler:, bundle:, system: nil, message:, output:)
      end

      def fail_result(message, output: nil)
        report(message)
        Result.new(ok: false, changed: false, bundler: nil, bundle: nil, system: nil, message:, output:)
      end

      def join_output(*parts) = parts.flatten.compact.map(&:to_s).reject(&:empty?).join("\n").strip

      def report(message) = Master::Trace::Dmesg.status("deps0", message, io: @out)
    end
  end
end
