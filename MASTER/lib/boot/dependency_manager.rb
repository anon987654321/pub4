# frozen_string_literal: true

require "digest"
require "fileutils"
require "open3"
require "rbconfig"
require "rubygems"

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
        EACCES
      /ix.freeze

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

        with_lock do
          bundler = ensure_bundler
          return bundler unless bundler.ok

          bundle = ensure_bundle
          return bundle if bundle.ok

          return bundle unless native_build_failure?(bundle.output)

          system = install_system_packages
          return bundle unless system[:ok]

          retry_bundle = ensure_bundle
          Result.new(
            ok: retry_bundle.ok,
            changed: bundler.changed || system[:changed] || retry_bundle.changed,
            bundler: bundler.bundler,
            bundle: retry_bundle.bundle,
            system: system,
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
            return fail_result("bundle update failed; system dependencies unavailable", output: output) unless system[:ok]

            ok, stdout, stderr = run_bundle(*args)
            output = join_output(output, join_output(stdout, stderr))
          end

          if ok
            ok_result("bundle updated", changed: true, bundle: true, output: output, bundler: bundler.bundler)
          else
            fail_result("bundle update failed", output: output)
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

      def status
        bundler_version = locked_bundler_version
        bundle_ok, bundle_output, = run_bundle("check")
        {
          ruby: RUBY_VERSION,
          ruby_required: locked_ruby_version,
          bundler: bundler_version,
          bundler_installed: bundler_path(bundler_version),
          bundle_ok: bundle_ok,
          bundle_output: bundle_output,
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

      def ensure_bundler
        version = locked_bundler_version
        return ok_result("no Bundler pin", changed: false) if version.empty?
        return ok_result("bundler #{version} already installed", changed: false, bundler: version) if bundler_path(version)

        report("installing bundler #{version}")
        gem = gem_command
        return fail_result("gem executable missing; install RubyGems or use MASTER/bin/ruby") unless gem

        ok, stdout, stderr = run(
          [gem, "install", "bundler", "-v", version, "--no-document", "--user-install"],
          chdir: @root,
          env: user_gem_env,
        )
        output = join_output(stdout, stderr)
        unless ok
          return fail_result(
            "bundler #{version} installation failed",
            output: output,
          )
        end

        Gem::Specification.reset
        if bundler_path(version)
          ok_result("bundler #{version} installed", changed: true, bundler: version, output: output)
        else
          fail_result("bundler #{version} installed but its executable is unavailable",
                      output: output)
        end
      end

      def ensure_bundle
        ok, stdout, stderr = run_bundle("check")
        return ok_result("bundle clean", changed: false, bundle: true, output: join_output(stdout, stderr)) if ok

        install_bundle
      end

      def install_bundle
        report("installing bundle for #{File.basename(@root)}")
        ok, stdout, stderr = run_bundle("install",
                                        "--jobs", bundle_jobs.to_s,
                                        "--retry", "3")
        output = join_output(stdout, stderr)
        if ok
          ok_result("bundle installed", changed: true, bundle: true, output: output)
        elsif permission_failure?(output)
          install_to_user_path(output)
        else
          message = dependency_conflict?(output) ?
            "bundle dependency constraints conflict; no automatic lockfile rewrite was attempted" :
            "bundle install failed"
          fail_result(message, output: output)
        end
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
          ok_result("bundle installed in user path", changed: true, bundle: true, output: output)
        else
          message = dependency_conflict?(output) ?
            "bundle dependency constraints conflict; no automatic lockfile rewrite was attempted" :
            "bundle install failed in user path"
          fail_result(message, output: output)
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
        return nil if version.to_s.empty?

        Gem.bin_path("bundler", "bundle", version)
      rescue Gem::GemNotFoundException, Gem::Exception
        user = File.join(user_gem_bin, "bundle")
        File.executable?(user) ? user : nil
      end

      def gem_command
        candidate = File.join(RbConfig::CONFIG.fetch("bindir"), Gem.default_exec_format.sub("@", "gem"))
        return candidate if File.executable?(candidate)

        @command_path.call("gem")
      end

      def user_gem_bin
        File.join(Gem.user_dir, "bin")
      rescue StandardError
        File.join(@home, ".gem", "ruby", RbConfig::CONFIG.fetch("ruby_version", RUBY_VERSION), "bin")
      end

      def user_gem_env
        { "PATH" => [user_gem_bin, @env.fetch("PATH", "")].reject(&:empty?).join(File::PATH_SEPARATOR) }
      end

      def bundle_env
        env = user_gem_env.dup

        # A user's global ~/.bundle/config, deployment variables, or a stale
        # BUNDLE_PATH can silently change what boot installs or loads. MASTER
        # owns its dependency context, while still allowing explicit credential
        # and build variables outside this list to flow through.
        BUNDLE_CONTEXT_KEYS.each { |key| env[key] = nil }
        env.merge!(
          "BUNDLE_GEMFILE" => File.join(@root, "Gemfile"),
          "BUNDLE_RETRY" => "3",
          "BUNDLE_JOBS" => bundle_jobs.to_s,
          "BUNDLE_APP_CONFIG" => File.join(bundle_config_root, "app"),
          "BUNDLE_USER_CONFIG" => File.join(bundle_config_root, "global"),
        )
        env
      end

      def bundle_config_root
        File.join(
          @home,
          ".master",
          "bundler",
          Digest::SHA256.hexdigest(@root)[0, 16],
        )
      end

      def bundle_jobs
        @env["MASTER_LOW_RESOURCE"] == "1" ? 2 : 4
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
            privileged(["apt-get", "update"], "apt-get"),
            privileged(["apt-get", "install", "-y", *packages], "apt-get")
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
        return :arch if @command_path.call("pacman")
      end

      def with_lock
        lock_path = File.join(@home, ".master", "dependency.lock")
        FileUtils.mkdir_p(File.dirname(lock_path), mode: 0o700)
        File.open(lock_path, File::RDWR | File::CREAT, 0o600) do |lock|
          lock.flock(File::LOCK_EX)
          yield
        end
      end

      def capture(argv, chdir:, env:)
        stdout, stderr, status = Open3.capture3(env, *argv, chdir: chdir)
        [status.success?, stdout, stderr]
      end

      def which(name) = @env.fetch("PATH", "").split(File::PATH_SEPARATOR).lazy.map { |dir|
        path = File.join(dir, name)
        path if File.file?(path) && File.executable?(path)
      }.find(&:itself)

      def run(command, chdir:, env:)
        @runner.call(command, chdir: chdir, env: env)
      end

      def ok_result(message, changed:, bundler: nil, bundle: nil, output: nil)
        Result.new(ok: true, changed:, bundler:, bundle:, system: nil, message:, output:)
      end

      def fail_result(message, output: nil)
        report(message)
        Result.new(ok: false, changed: false, bundler: nil, bundle: nil, system: nil, message:, output:)
      end

      def join_output(stdout, stderr) = [stdout, stderr].compact.reject(&:empty?).join("
").strip

      def report(message) = @out.puts("deps0: #{message}")
    end
  end
end
