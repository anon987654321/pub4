# frozen_string_literal: true

require_relative "test_helper"
require "tmpdir"
require "fileutils"
require_relative "../lib/boot/dependency_manager"

class TestDependencyManager < Minitest::Test
  MANAGER = Master::Boot::DependencyManager

  def setup
    @root = Dir.mktmpdir("master-deps-")
    File.write(File.join(@root, "Gemfile"), "source \"https://rubygems.org\"\n")
    File.write(File.join(@root, "Gemfile.lock"), <<~LOCK)
      GEM
        remote: https://rubygems.org/

      DEPENDENCIES

      RUBY VERSION
        ruby 4.0.5

      BUNDLED WITH
        4.0.5
    LOCK
    @commands = []
  end

  def teardown = FileUtils.rm_rf(@root)

  def fake_manager(responses, bundler: true)
    manager = MANAGER.new(
      root: @root,
      env: { "PATH" => "/bin", "MASTER_AUTO_INSTALL" => "1", "MASTER_AUTO_BUNDLE" => "1" },
      out: StringIO.new,
      home: @root,
      command_path: ->(_name) { "/fake/gem" },
      runner: lambda do |argv, chdir:, env:|
        @commands << [argv, chdir, env]
        responses.shift || [true, "", ""]
      end,
    )
    manager.define_singleton_method(:bundler_path) do |_version|
      bundler ? "/fake/bundle" : nil
    end
    manager
  end

  def test_watcher_gems_are_locked_with_ffi_in_both_bundles
    [File.join(Master::ROOT, "Gemfile.lock"), File.join(Master::ROOT, "web", "Gemfile.lock")].each do |path|
      source = File.read(path)

      assert_match(/rb-inotify \(0\.10\.1\)\n\s+ffi \(~> 1\.0\)/, source, "#{path} must lock rb-inotify with ffi")
      assert_match(/rb-kqueue \(0\.2\.8\)\n\s+ffi \(>= 0\.5\.0\)/, source, "#{path} must lock rb-kqueue with ffi")
      assert_includes source, "rb-inotify (~> 0.10)"
      assert_includes source, "rb-kqueue (~> 0.2)"
    end
  end

  def test_watcher_gems_use_install_if_across_master_bundles
    [File.join(Master::ROOT, "Gemfile"), File.join(Master::ROOT, "web", "Gemfile")].each do |path|
      source = File.read(path)

      assert_match(
        /install_if -> \{ RUBY_PLATFORM =~ \/bsd\|dragonfly\/i \} do\n\s+gem "rb-kqueue", "~> 0\.2"/,
        source,
        "#{path} must declare rb-kqueue through Bundler install_if"
      )
      assert_match(
        /install_if -> \{ RUBY_PLATFORM =~ \/linux\/ && !RUBY_PLATFORM\.include\?\("android"\) \} do\n\s+gem "rb-inotify", "~> 0\.10"/,
        source,
        "#{path} must declare rb-inotify through Bundler install_if"
      )
    end
  end

  def test_dilla_music_dependencies_stay_inside_the_dilla_group
    source = File.read(File.join(Master::ROOT, "Gemfile"))
    group = source[/group :dilla do\n(.*?)^end/m, 1].to_s

    assert_includes group, 'gem "head_music", "~> 15.1"'
    assert_includes group, 'gem "wavefile", "~> 1.1"'
    assert_match(/group :dilla do/, source)
  end

  def test_edge_tts_isolated_to_tts_group_in_both_master_bundles
    [File.join(Master::ROOT, "Gemfile"), File.join(Master::ROOT, "web", "Gemfile")].each do |path|
      source = File.read(path)
      assert_match(
        /group :tts do\n\s+gem "rb-edge-tts", "= 1\.0\.1"\nend/,
        source,
        "#{path} must keep Edge TTS out of the default Rails bundle"
      )
    end
  end

  def test_bundle_commands_ignore_ambient_configuration_and_use_master_context
    manager = MANAGER.new(
      root: @root,
      env: {
        "PATH" => "/bin",
        "MASTER_AUTO_INSTALL" => "1",
        "MASTER_AUTO_BUNDLE" => "1",
        "BUNDLE_FROZEN" => "1",
        "BUNDLE_DEPLOYMENT" => "1",
        "BUNDLE_PATH" => "/tmp/wrong-bundle",
        "BUNDLE_WITHOUT" => "test",
        "BUNDLE_VERSION" => "system",
        "BUNDLE_USER_CONFIG" => "/tmp/wrong-config",
      },
      out: StringIO.new,
      home: @root,
      command_path: ->(_name) { "/fake/gem" },
      runner: lambda do |argv, chdir:, env:|
        @commands << [argv, chdir, env]
        [true, "The Gemfile's dependencies are satisfied", ""]
      end,
    )
    manager.define_singleton_method(:bundler_path) { |_version| "/fake/bundle" }

    result = manager.ensure!

    assert result.success?
    bundle_env = @commands.last[2]
    %w[
      BUNDLE_FROZEN
      BUNDLE_DEPLOYMENT
      BUNDLE_PATH
      BUNDLE_WITHOUT
      BUNDLE_VERSION
    ].each { |key| assert_nil bundle_env[key], "#{key} must not leak into MASTER boot" }
    assert_equal File.join(@root, "Gemfile"), bundle_env["BUNDLE_GEMFILE"]
    assert_match(%r{/\.master/bundler/[0-9a-f]{16}/gems$}, bundle_env["GEM_HOME"])
    assert_includes bundle_env["GEM_PATH"], bundle_env["GEM_HOME"]
    assert_match(%r{/\.master/bundler/[0-9a-f]{16}/app$}, bundle_env["BUNDLE_APP_CONFIG"])
    assert_match(%r{/\.master/bundler/[0-9a-f]{16}/global$}, bundle_env["BUNDLE_USER_CONFIG"])
    assert_match(%r{/\.master/bundler/[0-9a-f]{16}/gems$}, bundle_env["BUNDLE_PATH"])
    assert_equal "1", bundle_env["BUNDLE_DISABLE_SHARED_GEMS"]
  end

  def test_activation_environment_reuses_the_sanitized_bundle_context
    env = {
      "PATH" => "/bin",
      "BUNDLE_FROZEN" => "1",
      "BUNDLE_PATH" => "/tmp/wrong-bundle",
      "BUNDLE_WITHOUT" => "tts",
      "BUNDLE_VERSION" => "system",
    }
    manager = MANAGER.new(root: @root, env:, out: StringIO.new, home: @root)

    assert manager.activate_environment!

    assert_equal File.join(@root, "Gemfile"), env["BUNDLE_GEMFILE"]
    assert_match(%r{/\.master/bundler/[0-9a-f]{16}/app$}, env["BUNDLE_APP_CONFIG"])
    assert_match(%r{/\.master/bundler/[0-9a-f]{16}/global$}, env["BUNDLE_USER_CONFIG"])
    assert_match(%r{/\.master/bundler/[0-9a-f]{16}/gems$}, env["BUNDLE_PATH"])
    assert_equal "1", env["BUNDLE_DISABLE_SHARED_GEMS"]
    assert_nil env["BUNDLE_FROZEN"]
    assert_nil env["BUNDLE_PATH"]
    assert_nil env["BUNDLE_WITHOUT"]
    assert_nil env["BUNDLE_VERSION"]
  end

  def test_bundle_store_isolated_by_ruby_installation
    rbenv = MANAGER.new(root: @root, env: { "PATH" => "/bin" }, out: StringIO.new, home: @root)
    homebrew = MANAGER.new(root: @root, env: { "PATH" => "/bin" }, out: StringIO.new, home: @root)

    rbenv.define_singleton_method(:ruby_identity) { "/Users/mac/.rbenv/versions/4.0.5/bin/ruby\\0/Users/mac/.rbenv/versions/4.0.5\\0libruby.4.0.dylib" }
    homebrew.define_singleton_method(:ruby_identity) { "/opt/homebrew/opt/ruby/bin/ruby\\0/opt/homebrew/Cellar/ruby/4.0.5\\0libruby.4.0.dylib" }

    refute_equal rbenv.send(:bundle_config_root), homebrew.send(:bundle_config_root)
  end

  def test_join_output_accepts_multiple_output_parts
    manager = MANAGER.new(root: @root, env: {}, out: StringIO.new)

    assert_equal "one\ntwo\nthree",
                 manager.send(:join_output, "one", "", nil, "two", "three")
  end

  def test_incompatible_native_bundle_is_repaired_before_boot
    responses = [
      [true, "The Gemfile's dependencies are satisfied", ""],
      [false, "", "linked to incompatible /opt/homebrew/Cellar/ruby/4.0.5/lib/libruby.4.0.dylib"],
      [true, "Bundle pristine", ""],
      [true, "", ""],
    ]
    manager = fake_manager(responses)

    result = manager.send(:ensure_bundle)

    assert result.success?
    assert result.changed
    assert_equal ["check"], @commands[0].first[1..]
    assert_equal [RbConfig.ruby, "-rbundler/setup", "-rjson", "-e", "exit"], @commands[1].first
    assert_equal ["install", "--jobs", "4", "--retry", "3"], @commands[2].first[1..]
    assert_equal [RbConfig.ruby, "-rbundler/setup", "-rjson", "-e", "exit"], @commands[3].first
  end

  def test_stale_native_bundle_cleanup_removes_private_gems
    manager = MANAGER.new(
      root: @root,
      env: { "PATH" => "/bin", "MASTER_AUTO_INSTALL" => "1", "MASTER_AUTO_BUNDLE" => "1" },
      out: StringIO.new,
      home: @root,
    )
    path = manager.send(:bundle_gems_path)
    FileUtils.mkdir_p(path)
    File.write(File.join(path, "stale.bundle"), "homebrew")

    assert manager.send(:discard_stale_native_bundle!)
    refute Dir.exist?(path)
  end

  def test_bundler_path_rejects_stale_spec_without_executable
    manager = MANAGER.new(root: @root, env: { "PATH" => "/bin" }, out: StringIO.new, home: @root)
    stale = Gem::Specification.new("bundler", Gem::Version.new("4.0.5"))
    stale.define_singleton_method(:full_gem_path) { "/tmp/master-stale-bundler" }

    manager.define_singleton_method(:bundler_spec) { |_version| stale }

    assert_nil manager.send(:bundler_path, "4.0.5")
  end

  def test_bundle_process_uses_the_active_ruby
    manager = MANAGER.new(root: @root, env: { "PATH" => "/usr/bin:/opt/homebrew/bin" }, out: StringIO.new, home: @root)
    env = manager.send(:bundle_env)

    assert_equal RbConfig.ruby, env["RUBY"]
    assert_equal File.dirname(RbConfig.ruby), env["PATH"].split(File::PATH_SEPARATOR).first
  end


  def test_clean_bundle_does_not_install_or_touch_lock
    manager = fake_manager([[true, "The Gemfile's dependencies are satisfied", ""]])
    before = File.read(File.join(@root, "Gemfile.lock"))

    result = manager.ensure!

    assert result.success?
    assert_equal 1, @commands.length
    assert_equal ["check"], @commands.first.first[1..]
    assert_equal before, File.read(File.join(@root, "Gemfile.lock"))
  end

  def test_install_rebuilds_native_bundle_before_reporting_success
    responses = [
      [false, "", "dependencies missing"],
      [true, "Bundle complete", ""],
      [false, "", "linked to incompatible libruby"],
      [true, "Installed native extensions", ""],
      [true, "", ""],
    ]
    manager = fake_manager(responses)

    result = manager.ensure!

    assert result.success?
    assert_equal ["check"], @commands[0].first[1..]
    assert_equal ["install", "--jobs", "4", "--retry", "3"], @commands[1].first[1..]
    assert_equal ["install", "--jobs", "4", "--retry", "3"], @commands[3].first[1..]
  end

  def test_native_abi_repair_failure_does_not_install_os_packages
    responses = [
      [false, "", "dependencies missing"],
      [true, "Bundle complete", ""],
      [false, "", "linked to incompatible libruby"],
      [false, "", "pristine failed"],
    ]
    manager = fake_manager(responses)
    manager.define_singleton_method(:package_command) do
      raise "OS package recovery must not run for ABI repair failure"
    end

    result = manager.ensure!

    refute result.success?
    assert_includes result.message, "native extension repair failed"
  end

  def test_bundler_path_rejects_an_executable_without_the_pinned_spec
    manager = MANAGER.new(
      root: @root,
      env: { "PATH" => "/bin", "MASTER_AUTO_INSTALL" => "1", "MASTER_AUTO_BUNDLE" => "1" },
      out: StringIO.new,
      home: @root,
    )
    manager.define_singleton_method(:bundler_spec) { |_version| nil }

    assert_nil manager.send(:bundler_path, "4.0.5")
  end

  def test_missing_bundler_installs_into_separate_tool_store
    installed = false
    manager = fake_manager([[true, "installed", ""]], bundler: false)
    manager.define_singleton_method(:bundler_path) do |_version|
      installed ? "/fake/bundle" : nil
    end
    manager.define_singleton_method(:gem_command) { "/fake/gem" }
    manager.define_singleton_method(:run) do |command, chdir:, env:|
      @commands << [command, chdir, env]
      installed = true
      [true, "installed", ""]
    end

    result = manager.send(:ensure_bundler)

    assert result.success?
    command = @commands.first.first
    assert_equal ["/fake/gem", "install", "bundler", "-v", "4.0.5", "--no-document"], command[0, 6]
    assert_equal "--install-dir", command[6]
    assert_match(%r{/.master/bundler/[0-9a-f]{16}/bundler$}, command[7])
  end

  def test_missing_bundle_installs_bundler_then_rechecks
    installed = false
    responses = [[true, "installed", ""], [true, "The Gemfile's dependencies are satisfied", ""]]
    manager = fake_manager(responses, bundler: false)
    manager.define_singleton_method(:bundler_path) do |_version|
      installed ? "/fake/bundle" : nil
    end
    manager.define_singleton_method(:gem_command) { "/fake/gem" }
    manager.define_singleton_method(:run) do |command, chdir:, env:|
      @commands << [command, chdir, env]
      installed = true if command.first(2) == ["/fake/gem", "install"]
      responses.shift || [true, "", ""]
    end

    result = manager.ensure!

    assert result.success?
    bundler_command = @commands.find { |row| row.first.first(2) == ["/fake/gem", "install"] }
    refute_nil bundler_command
    assert_equal @root, bundler_command[1]
    assert_equal ["/fake/bundle", "check"], @commands.last.first
  end

  def test_resolver_conflict_fails_with_explicit_non_mutating_message
    manager = fake_manager([
      [false, "", "Could not find compatible versions for gem 'ruby_llm'"]
    ])

    result = manager.ensure!

    refute result.success?
    assert_includes result.message, "constraints conflict"
    assert_includes result.message, "no automatic lockfile rewrite"
    assert_equal ["check"], @commands.first.first[1..]
    assert_equal ["install", "--jobs", "4", "--retry", "3"], @commands.last.first[1..]
  end

  def test_native_build_failure_installs_system_packages_and_retries
    responses = [
      [false, "", "extconf failed: sqlite3.h not found"],
      [false, "", "extconf failed: sqlite3.h not found"],
      [true, "system packages installed", ""],
      [true, "Bundle complete", ""],
    ]
    manager = fake_manager(responses)
    manager.define_singleton_method(:package_command) do
      [["pkg", "install", "-y", "sqlite"], "pkg"]
    end

    result = manager.ensure!

    refute_empty @commands
    assert result.success?
    assert @commands.any? { |row| row.first == ["pkg", "install", "-y", "sqlite"] }
  end

  def test_debian_runs_update_before_install
    manager = fake_manager([
      [true, "Hit", ""],
      [true, "Installed", ""]
    ])
    manager.define_singleton_method(:package_manager_name) { :debian }
    manager.define_singleton_method(:privileged) do |command, label|
      [["sudo", "-n", *command], label]
    end
    manager.define_singleton_method(:run_bundle) do |*args|
      [false, "", "extconf failed: missing compiler"]
    end

    result = manager.send(:install_system_packages)

    assert result[:ok]
    assert_equal [
      ["sudo", "-n", "apt-get", "update"],
      ["sudo", "-n", "apt-get", "install", "-y", *Master::Boot::DependencyManager::SYSTEM_PACKAGES[:debian]]
    ], @commands.map(&:first)
  end

  def test_openbsd_uses_noninteractive_pkg_add_with_privilege
    manager = fake_manager([])
    manager.define_singleton_method(:package_manager_name) { :openbsd }
    manager.define_singleton_method(:root?) { false }
    manager.define_singleton_method(:privileged) do |command, label|
      [[ "doas", "-n", *command ], label]
    end

    argv, label = manager.send(:package_command)
    assert_equal "pkg_add", label
    assert_equal "doas", argv.first
    assert_includes argv, "gmake"
    assert_includes argv, "pkgconf"
  end

  def test_termux_uses_pkg_without_privilege
    manager = fake_manager([])
    manager.define_singleton_method(:package_manager_name) { :termux }

    argv, label = manager.send(:package_command)
    assert_equal "pkg", label
    assert_equal %w[pkg install -y], argv.first(3)
    assert_includes argv, "sqlite"
  end

  def test_boot_probe_uses_the_real_master_boot_path
    source = File.read(File.join(Master::ROOT, "bin", "deps"))

    assert_match(/when "boot"/, source)
    assert_includes source, 'system(cli, "--fast")'
    assert_match(%r{cli = File\.join\(ROOT, "bin", "cli"\)}, source)
  end

  def test_disabled_automatic_boot_is_a_noop
    manager = fake_manager([])
    manager.instance_variable_get(:@env)["MASTER_AUTO_INSTALL"] = "0"

    result = manager.ensure!

    assert result.success?
    assert_equal "auto-install disabled", result.message
    assert_empty @commands
  end
end
