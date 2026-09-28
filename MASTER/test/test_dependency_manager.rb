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
        4.0.7
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

  def test_clean_bundle_does_not_install_or_touch_lock
    manager = fake_manager([[true, "The Gemfile's dependencies are satisfied", ""]])
    before = File.read(File.join(@root, "Gemfile.lock"))

    result = manager.ensure!

    assert result.success?
    assert_equal 1, @commands.length
    assert_equal ["check"], @commands.first.first[1..]
    assert_equal before, File.read(File.join(@root, "Gemfile.lock"))
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
    assert @commands.any? { |row| row.first.first(2) == ["/fake/gem", "install"] }
    assert_equal ["/fake/bundle", "check"], @commands.last.first
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

  def test_disabled_automatic_boot_is_a_noop
    manager = fake_manager([])
    manager.instance_variable_get(:@env)["MASTER_AUTO_INSTALL"] = "0"

    result = manager.ensure!

    assert result.success?
    assert_equal "auto-install disabled", result.message
    assert_empty @commands
  end
end
