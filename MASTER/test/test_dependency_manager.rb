# frozen_string_literal: true

require_relative "test_helper"
require "tmpdir"
require "open3"
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

  def test_dependency_bootstrap_does_not_preload_open3_or_timeout
    source = File.read(File.join(Master::ROOT, "lib", "boot", "dependency_manager.rb"))

    refute_includes source, 'require "open3"'
    assert_includes source, "Process.spawn"
    assert_includes source, "IO.pipe"
  end

  def test_master_requires_the_pinned_ruby_in_gemfile_and_lock
    gemfile = File.read(File.join(Master::ROOT, "Gemfile"))
    lock = File.read(File.join(Master::ROOT, "Gemfile.lock"))

    assert_match(/^ruby ">= 3\.3", "< 4\.1"$/, gemfile)
    locked = lock[/^RUBY VERSION\n  ruby (\d+\.\d+\.\d+)$/m, 1]
    refute_nil locked, "Gemfile.lock must record the exact Ruby that resolved it"
    assert Gem::Requirement.new(">= 3.3", "< 4.1").satisfied_by?(Gem::Version.new(locked))
    assert_equal locked, File.read(File.join(Master::ROOT, ".ruby-version")).strip
  end

  def test_watcher_gems_are_locked_with_ffi_in_both_bundles
    [File.join(Master::ROOT, "Gemfile.lock"), File.join(Master::ROOT, "..", "RAILS", "master", "Gemfile.lock")].each do |path|
      source = File.read(path)

      assert_match(/rb-inotify \(0\.10\.1\)\n\s+ffi \(~> 1\.0\)/, source, "#{path} must lock rb-inotify with ffi")
      assert_match(/rb-kqueue \(0\.2\.8\)\n\s+ffi \(>= 0\.5\.0\)/, source, "#{path} must lock rb-kqueue with ffi")
      assert_includes source, "rb-inotify (~> 0.10)"
      assert_includes source, "rb-kqueue (~> 0.2)"
    end
  end

  def test_master_lock_declares_openbsd_platform_and_source_sqlite
    source = File.read(File.join(Master::ROOT, "Gemfile.lock"))
    platforms = source[/^PLATFORMS\n(.*?)\n\nDEPENDENCIES/m, 1].to_s

    assert_includes platforms, "x86_64-openbsd"
    assert_includes platforms, "aarch64-linux"
    assert_match(/^    sqlite3 \(2\.9\.4\)$/m, source)
    assert_match(/^    mini_portile2 \(2\.8\.9\)$/m, source)
    assert_match(/^  sqlite3 \(2\.9\.4\) sha256=[0-9a-f]+$/m, source)
    assert_match(/^  mini_portile2 \(2\.8\.9\) sha256=[0-9a-f]+$/m, source)
  end

  def test_watcher_gems_use_install_if_across_master_bundles
    [File.join(Master::ROOT, "Gemfile"), File.join(Master::ROOT, "..", "RAILS", "master", "Gemfile")].each do |path|
      source = File.read(path)

      assert_match(
        /install_if -> \{ RUBY_PLATFORM =~ \/bsd\|dragonfly\/i \} do\n\s+gem "rb-kqueue", "~> 0\.2"/,
        source,
        "#{path} must declare rb-kqueue through Bundler install_if",
      )
      assert_match(
        /install_if -> \{ RUBY_PLATFORM =~ \/linux\/ && !RUBY_PLATFORM\.include\?\("android"\) \} do\n\s+gem "rb-inotify", "~> 0\.10"/,
        source,
        "#{path} must declare rb-inotify through Bundler install_if",
      )
    end
  end

  def test_dilla_takes_no_gems
    source = File.read(File.join(Master::ROOT, "Gemfile"))
    lock = File.read(File.join(Master::ROOT, "Gemfile.lock"))

    refute_match(/group :dilla/, source)
    %w[coltrane midilib wavefile head_music].each do |gem_name|
      refute_match(/^    #{gem_name} /, lock, "#{gem_name} is a gem dilla.rb no longer reads")
    end
  end

  def test_edge_tts_isolated_to_tts_group_in_both_master_bundles
    [File.join(Master::ROOT, "Gemfile"), File.join(Master::ROOT, "..", "RAILS", "master", "Gemfile")].each do |path|
      source = File.read(path)
      assert_match(
        /group :tts do\n\s+gem "rb-edge-tts", "= 1\.0\.1"\nend/,
        source,
        "#{path} must keep Edge TTS out of the default Rails bundle",
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
        "RUBYOPT" => "-rbundler/setup",
        "RUBYLIB" => "/ambient/bundler/lib",
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
      BUNDLE_DEPLOYMENT
      BUNDLE_VERSION
      RUBYOPT
      RUBYLIB
    ].each { |key| assert_nil bundle_env[key], "#{key} must not leak into MASTER boot" }
    # Named with a nil value: the runner unsets an inherited key only when it is listed.
    %w[RUBYOPT RUBYLIB].each { |key| assert bundle_env.key?(key), "#{key} must be unset for the child bundle" }
    assert_equal File.join(@root, "Gemfile"), bundle_env["BUNDLE_GEMFILE"]
    assert_match(%r{/\.master/bundler/[0-9a-f]{16}/gems$}, bundle_env["GEM_HOME"])
    assert_includes bundle_env["GEM_PATH"], bundle_env["GEM_HOME"]
    assert_match(%r{/\.master/bundler/[0-9a-f]{16}/app$}, bundle_env["BUNDLE_APP_CONFIG"])
    assert_match(%r{/\.master/bundler/[0-9a-f]{16}/global$}, bundle_env["BUNDLE_USER_CONFIG"])
    assert_match(%r{/\.master/bundler/[0-9a-f]{16}/gems$}, bundle_env["BUNDLE_PATH"])
    assert_equal "1", bundle_env["BUNDLE_DISABLE_SHARED_GEMS"]
    assert_equal "true", bundle_env["BUNDLE_FROZEN"]
  end

  # The store key hashes the git common dir, so a process that has not loaded
  # open3 must still find it; otherwise it keys a second, empty store and
  # reinstalls every gem there.
  def test_the_store_key_reads_the_git_common_dir_in_a_bare_process
    lib = File.expand_path("../lib", __dir__)
    script = 'require "boot/dependency_manager"; ' \
             "print Master::Boot::DependencyManager.new(root: ARGV[0]).send(:git_common_dir).inspect"
    out = IO.popen({ "RUBYOPT" => nil, "RUBYLIB" => nil }, [RbConfig.ruby, "-I", lib, "-e", script, Master::ROOT], err: File::NULL, &:read)

    refute_equal "nil", out
  end

  def test_activation_refreshes_rubygems_to_the_master_bundle
    manager = MANAGER.new(root: Master::ROOT, env: ENV, out: StringIO.new)

    manager.activate_environment!

    assert_equal ENV["GEM_HOME"], Gem.dir
    assert_includes Gem.path, ENV["GEM_HOME"]
  end

  def store_key_for(root, home)
    MANAGER.new(root: root, env: { "PATH" => ENV.fetch("PATH") }, out: StringIO.new, home: home)
           .send(:bundle_config_root)
  end

  def git!(*args, chdir:)
    out, status = Open3.capture2e("git", "-c", "user.email=t@t", "-c", "user.name=t", *args, chdir: chdir)
    assert status.success?, "git #{args.join(" ")} failed: #{out}"
  end

  # bin/master, bin/check, rake and the tests all build a
  # DependencyManager from their own MASTER/ directory. A /fix worker runs in a
  # linked worktree under the system temp directory; it must land on the main
  # checkout's gem store instead of running a fresh bundle install.
  def test_linked_worktree_and_temp_checkout_share_the_main_checkouts_store_key
    Dir.mktmpdir("master-store-key-") do |dir|
      main = File.join(dir, "main")
      FileUtils.mkdir_p(File.join(main, "MASTER"))
      File.write(File.join(main, "MASTER", "Gemfile"), "source \"https://rubygems.org\"\n")
      git!("init", "-q", "-b", "main", chdir: main)
      git!("add", "-A", chdir: main)
      git!("commit", "-q", "-m", "seed", chdir: main)

      linked = File.join(dir, "linked")
      git!("worktree", "add", "-q", "-b", "linked", linked, chdir: main)
      temp_parent = Dir.mktmpdir("pub4-master-fix-")
      temp = File.join(temp_parent, "checkout")
      begin
        git!("worktree", "add", "-q", "-b", "fixtemp", temp, chdir: main)

        home = File.join(dir, "home")
        key = store_key_for(File.join(main, "MASTER"), home)

        assert_equal key, store_key_for(File.join(linked, "MASTER"), home)
        assert_equal key, store_key_for(File.join(temp, "MASTER"), home)
        assert_equal key, store_key_for(main, home), "the toplevel and its MASTER/ directory are one checkout"
      ensure
        FileUtils.rm_rf(temp_parent)
      end
    end
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
    assert_equal "true", env["BUNDLE_FROZEN"]
    assert_equal "tts", env["BUNDLE_WITHOUT"], "an explicit BUNDLE_WITHOUT is the caller's choice and survives"
    assert_nil env["BUNDLE_VERSION"]
  end

  def test_direct_tests_bootstrap_master_bundle_before_versioned_gems
    source = File.read(File.join(Master::ROOT, "test", "test_helper.rb"))
    bundle_index = source.index('require "bundler/setup"')
    minitest_index = source.index('gem "minitest", "~> 5.25"')

    refute_nil bundle_index
    refute_nil minitest_index
    assert_operator bundle_index, :<, minitest_index
  end

  def test_bundle_store_is_shared_by_worktrees_of_one_checkout
    main = MANAGER.new(root: File.join(@root, "repo", "MASTER"), env: { "PATH" => "/bin" }, out: StringIO.new, home: @root)
    worktree = MANAGER.new(root: File.join(@root, "tmp", "checkout", "MASTER"), env: { "PATH" => "/bin" }, out: StringIO.new, home: @root)
    clone = MANAGER.new(root: File.join(@root, "other", "repo", "MASTER"), env: { "PATH" => "/bin" }, out: StringIO.new, home: @root)
    common = File.join(@root, "repo", ".git")

    [main, worktree].each { |manager| manager.define_singleton_method(:git_common_dir) { common } }
    clone.define_singleton_method(:git_common_dir) { File.join(@root, "other", ".git") }

    assert_equal main.send(:bundle_config_root), worktree.send(:bundle_config_root)
    refute_equal main.send(:bundle_config_root), clone.send(:bundle_config_root)
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
    FileUtils.mkdir_p(manager.send(:bundle_gems_path))

    result = manager.send(:ensure_bundle)

    assert result.success?
    assert result.changed
    assert_equal ["check"], @commands[0].first[1..]
    assert_equal [RbConfig.ruby, "-rbundler/setup", "-rjson", "-e", "exit"], @commands[1].first
    assert_equal ["install", "--jobs", "4", "--retry", "3"], @commands[2].first[1..]
    assert_equal [RbConfig.ruby, "-rbundler/setup", "-rjson", "-e", "exit"], @commands[3].first
  end

  def test_stale_native_bundle_is_moved_aside_without_losing_bytes
    manager = MANAGER.new(
      root: @root,
      env: { "PATH" => "/bin", "MASTER_AUTO_INSTALL" => "1", "MASTER_AUTO_BUNDLE" => "1" },
      out: StringIO.new,
      home: @root,
    )
    path = manager.send(:bundle_gems_path)
    FileUtils.mkdir_p(path)
    marker = File.join(path, "stale.bundle")
    File.write(marker, "homebrew")

    assert manager.send(:discard_stale_native_bundle!)
    refute Dir.exist?(path)
    stale_path = Dir.glob("#{path}.stale-*").fetch(0)
    assert_equal "homebrew", File.read(File.join(stale_path, "stale.bundle"))
  end

  def test_non_abi_native_probe_failure_keeps_the_private_store
    manager = fake_manager([
      [true, "dependencies satisfied", ""],
      [false, "", "No such file or directory"],
    ])
    path = manager.send(:bundle_gems_path)
    FileUtils.mkdir_p(path)
    marker = File.join(path, "preserve.bundle")
    File.write(marker, "keep me")

    result = manager.send(:ensure_bundle)

    refute result.success?
    assert_match(/no ABI-stale evidence/, result.message)
    assert_equal "keep me", File.read(marker)
    assert_equal 2, @commands.length
  end

  def test_capture_kills_a_hung_process_group_at_its_deadline
    manager = MANAGER.new(root: @root, env: { "PATH" => ENV.fetch("PATH", "") }, out: StringIO.new, home: @root)
    ok, _stdout, stderr = manager.send(
      :capture, [RbConfig.ruby, "-e", "sleep 30"],
      chdir: @root, env: {}, deadline_seconds: 0.35,
    )

    refute ok
    assert_match(/process group killed after 0.35s deadline/, stderr)
  end

  def test_dependency_lock_wait_is_bounded
    manager = MANAGER.new(root: @root, env: {}, out: StringIO.new, home: @root)
    path = File.join(@root, ".master", "dependency.lock")
    FileUtils.mkdir_p(File.dirname(path))
    File.open(path, File::RDWR | File::CREAT, 0o600) do |lock|
      lock.flock(File::LOCK_EX)
      error = assert_raises(RuntimeError) do
        manager.send(:with_lock, wait_seconds: 0.08) { flunk "must not enter locked body" }
      end
      assert_match(/dependency lock held elsewhere/, error.message)
    end
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

  # vps_deploy_master.sh installs MASTER's bundle as the deploy user at the path
  # in MASTER/.bundle/config. The daemon runs as `master`, whose HOME has no
  # private store, so without this it tried a 177-gem install inside a probe
  # timeout (2026-10-12: TTS down, /health 503).
  def with_deploy_bundle(path_dir = Dir.mktmpdir("deploy-bundle-"))
    FileUtils.mkdir_p(File.join(@root, ".bundle"))
    File.write(File.join(@root, ".bundle", "config"), %(---\nBUNDLE_PATH: "#{path_dir}"\n))
    yield path_dir
  ensure
    FileUtils.rm_rf(path_dir)
  end

  def test_a_satisfied_deploy_bundle_is_used_read_only_without_a_private_store
    with_deploy_bundle do |dir|
      manager = fake_manager([[true, "The Gemfile's dependencies are satisfied", ""]])
      result = manager.ensure!

      assert result.success?, result.output.to_s
      refute(@commands.any? { |argv, *| argv.include?("install") }, "must not install")
      env = @commands.first[2]
      assert_equal dir, env["BUNDLE_PATH"]
      assert_equal "true", env["BUNDLE_FROZEN"]
      assert_equal "development:test", env["BUNDLE_WITHOUT"]
      assert_nil env["GEM_HOME"]
      assert env.key?("BUNDLE_APP_CONFIG"), "named with nil so the private app config is unset"
      assert_nil env["BUNDLE_APP_CONFIG"]
      refute(Dir.exist?(File.join(@root, ".master", "bundler")), "no private store may be created")
    end
  end

  def test_an_unsatisfied_deploy_bundle_the_user_cannot_write_fails_loudly_without_installing
    with_deploy_bundle do |dir|
      manager = fake_manager([[false, "", "Could not find ferrum-0.17.1 in locally installed gems"]])
      File.stub(:writable?, false) do
        result = manager.ensure!

        refute result.success?
        assert_includes result.message, dir
        assert_includes result.message, "run vps-deploy"
        assert_includes result.output, "Could not find ferrum"
        refute(@commands.any? { |argv, *| argv.include?("install") }, "must not install")
      end
    end
  end

  def test_bundle_commands_drop_the_parents_bundler_preload
    manager = fake_manager([[true, "ok", ""]])
    manager.instance_variable_get(:@env).merge!("BUNDLER_SETUP" => "/web/bundler/setup", "BUNDLE_BIN_PATH" => "/web/bundle")
    manager.ensure!

    env = @commands.first[2]
    %w[BUNDLER_SETUP BUNDLE_BIN_PATH BUNDLER_VERSION].each do |key|
      assert env.key?(key) && env[key].nil?, "#{key} must be unset for the child bundle"
    end
  end

  def test_clean_bundle_does_not_install_or_touch_lock
    manager = fake_manager([[true, "The Gemfile's dependencies are satisfied", ""]])
    before = File.read(File.join(@root, "Gemfile.lock"))

    result = manager.ensure!

    assert result.success?
    assert_equal ["check"], @commands.first.first[1..]
    assert_equal [RbConfig.ruby, "-rbundler/setup", "-rjson", "-e", "exit"], @commands.last.first
    assert_equal 2, @commands.length
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

  def test_install_repairs_when_the_install_command_itself_hits_stale_native_code
    responses = [
      [false, "", "dependencies missing"],
      [false, "", "linked to incompatible /opt/homebrew/Cellar/ruby/4.0.5/lib/libruby.4.0.dylib"],
      [true, "Bundle complete", ""],
      [true, "", ""],
    ]
    manager = fake_manager(responses)
    FileUtils.mkdir_p(manager.send(:bundle_gems_path))

    result = manager.ensure!

    assert result.success?
    assert result.changed
    assert_equal ["check"], @commands[0].first[1..]
    assert_equal ["install", "--jobs", "4", "--retry", "3"], @commands[1].first[1..]
    assert_equal ["install", "--jobs", "4", "--retry", "3"], @commands[2].first[1..]
  end

  def test_native_abi_repair_failure_does_not_install_os_packages
    responses = [
      [false, "", "dependencies missing"],
      [true, "Bundle complete", ""],
      [false, "", "linked to incompatible libruby"],
      [false, "", "pristine failed"],
    ]
    manager = fake_manager(responses)
    manager.define_singleton_method(:package_commands) do
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
    commands = @commands
    manager.define_singleton_method(:run) do |command, chdir:, env:|
      commands << [command, chdir, env]
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
    commands = @commands
    manager.define_singleton_method(:run) do |command, chdir:, env:|
      commands << [command, chdir, env]
      installed = true if command.first(2) == ["/fake/gem", "install"]
      responses.shift || [true, "", ""]
    end

    result = manager.ensure!

    assert result.success?
    bundler_command = @commands.find { |row| row.first.first(2) == ["/fake/gem", "install"] }
    refute_nil bundler_command
    assert_equal @root, bundler_command[1]
    assert_includes @commands.map(&:first), ["/fake/bundle", "check"]
  end

  def test_resolver_conflict_fails_with_explicit_non_mutating_message
    manager = fake_manager([
      [false, "", "dependencies missing"],
      [false, "", "Could not find compatible versions for gem 'ruby_llm'"],
    ])

    result = manager.ensure!

    refute result.success?
    assert_includes result.message, "constraints conflict"
    assert_includes result.message, "no automatic lockfile rewrite"
    assert_equal ["check"], @commands.first.first[1..]
    assert_equal ["install", "--jobs", "4", "--retry", "3"], @commands.last.first[1..]
  end

  # A missing header carries no ABI-stale line, so the private store stays and
  # the OS packages install straight after the failed bundle install.
  def test_native_build_failure_installs_system_packages_and_retries
    responses = [
      [false, "", "extconf failed: sqlite3.h not found"],
      [false, "", "extconf failed: sqlite3.h not found"],
      [true, "system packages installed", ""],
      [true, "The Gemfile's dependencies are satisfied", ""],
    ]

    manager = fake_manager(responses)
    manager.define_singleton_method(:package_commands) do
      [[["pkg", "install", "-y", "sqlite"], "pkg"]]
    end

    result = manager.ensure!

    refute_empty @commands
    assert result.success?
    assert @commands.any? { |row| row.first == ["pkg", "install", "-y", "sqlite"] }
  end

  def test_debian_runs_update_before_install
    manager = fake_manager([
      [true, "Hit", ""],
      [true, "Installed", ""],
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
      ["sudo", "-n", "apt-get", "install", "-y", *Master::Boot::DependencyManager::SYSTEM_PACKAGES[:debian]],
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
    assert_includes source, 'master, "--fast")'
    assert_match(%r{master = File\.join\(ROOT, "bin", "master"\)}, source)
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
