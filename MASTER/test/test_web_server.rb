# frozen_string_literal: true

require_relative "test_helper"
require "stringio"
require "tmpdir"

class TestWebServer < Minitest::Test
  def setup = @previous_web = ENV["MASTER_WEB"]

  def teardown
    @previous_web.nil? ? ENV.delete("MASTER_WEB") : ENV["MASTER_WEB"] = @previous_web
  end

  def test_openbsd_status_uses_dmesg_shape
    ENV["MASTER_WEB"] = "1"
    config = { "web_public_url" => "https://ai.brgen.no", "web_token" => "" }
    out = StringIO.new
    Master::CLI::WebServer.stub(:system, true) do
      Master::CLI::WebServer.openbsd_status(config:, host: "127.0.0.1", port: 53_187, io: out)
    end
    assert_includes out.string, "web0: https://ai.brgen.no, up"
  end

  def test_start_is_a_no_op_when_master_web_is_not_enabled
    ENV["MASTER_WEB"] = "0"
    io = StringIO.new
    Master::CLI::WebServer.start({}, io:)
    assert_empty io.string
  end

  def test_openbsd_status_reports_down_when_no_process_matches
    io = StringIO.new
    Master::CLI::WebServer.openbsd_status(config: {}, host: "127.0.0.1", port: 599_99, io:)
    assert_includes io.string, "web0: https://ai.brgen.no, down — run: doas rcctl start master"
  end

  def test_openbsd_status_reports_web_token_hint_when_configured
    io = StringIO.new
    config = { "web_token" => "a" * 12 }
    Master::CLI::WebServer.openbsd_status(config:, host: "127.0.0.1", port: 599_98, io:)
    assert_includes io.string, "web0: token set"
  end

  # Regression: spawn_local's env hash used to only add RAILS_ENV/
  # SECRET_KEY_BASE on top of the *inherited* environment, so the parent
  # MASTER process's own BUNDLE_GEMFILE/BUNDLE_PATH/RUBYLIB leaked straight
  # through. The spawned `bundle exec falcon` resolved against MASTER's
  # Gemfile.lock (no falcon dependency there), failed immediately with
  # Bundler::GemNotFoundException, and nothing surfaced it because
  # err: was File::NULL -- confirmed live before this fix (spawn_local
  # printed its success line and returned, but nothing was ever listening
  # on the port).
  def test_spawn_env_points_bundle_gemfile_at_web_dir_not_master
    web_dir = File.join(Master::RAILS_ROOT, "master")
    env = Master::CLI::WebServer.spawn_env(web_dir)
    assert_equal File.join(web_dir, "Gemfile"), env["BUNDLE_GEMFILE"]
  end

  def test_spawn_env_strips_all_bundle_isolation_keys
    env = Master::CLI::WebServer.spawn_env(File.join(Master::RAILS_ROOT, "master"))
    Master::Voice::TtsSupervisor::BUNDLE_ISOLATION_KEYS.each do |key|
      assert_nil env[key], "expected #{key} to be stripped from the spawn env"
    end
  end

  def test_persist_secret_writes_private_config_and_tightens_existing_mode
    Dir.mktmpdir("web-secret-mode") do |root|
      Master::CLI::WebServer.send(:persist_secret, "s" * 64, root:)
      path = File.join(root, ".master", "config.yml")
      assert_equal 0o600, File.stat(path).mode & 0o777
      assert_equal 0o700, File.stat(File.dirname(path)).mode & 0o777

      File.chmod(0o644, path)
      Master::CLI::WebServer.send(:persist_secret, "t" * 64, root:)
      assert_equal 0o600, File.stat(path).mode & 0o777
    end
  end

  def test_config_save_writes_private_file_mode
    Dir.mktmpdir("ground-config-mode") do |root|
      config = Master::Ground::Config.new(root)
      config["web_token"] = "token-for-mode-test"
      config.save!
      path = File.join(root, ".master", "config.yml")

      assert_equal 0o600, File.stat(path).mode & 0o777
      assert_equal 0o700, File.stat(File.dirname(path)).mode & 0o777

      File.chmod(0o644, path)
      config.save!
      assert_equal 0o600, File.stat(path).mode & 0o777
    end
  end
end
