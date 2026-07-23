# frozen_string_literal: true

require_relative "test_helper"
require "stringio"

class TestWebServer < Minitest::Test
  def test_start_is_a_no_op_when_master_web_is_not_enabled
    ENV["MASTER_WEB"] = "0"
    io = StringIO.new
    Master::CLI::WebServer.start({}, io:)
    assert_empty io.string
  ensure
    ENV.delete("MASTER_WEB")
  end

  def test_openbsd_status_reports_down_when_no_process_matches
    io = StringIO.new
    Master::CLI::WebServer.openbsd_status(config: {}, host: "127.0.0.1", port: 599_99, io:)
    assert_includes io.string, "down — run: doas rcctl start master"
  end

  def test_openbsd_status_reports_web_token_hint_when_configured
    io = StringIO.new
    config = { "web_token" => "a" * 12 }
    Master::CLI::WebServer.openbsd_status(config:, host: "127.0.0.1", port: 599_98, io:)
    assert_includes io.string, "web: token set"
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
    web_dir = File.join(Master::ROOT, "web")
    env = Master::CLI::WebServer.spawn_env(web_dir)
    assert_equal File.join(web_dir, "Gemfile"), env["BUNDLE_GEMFILE"]
  end

  def test_spawn_env_strips_all_bundle_isolation_keys
    env = Master::CLI::WebServer.spawn_env(File.join(Master::ROOT, "web"))
    Master::Voice::TtsSupervisor::BUNDLE_ISOLATION_KEYS.each do |key|
      assert_nil env[key], "expected #{key} to be stripped from the spawn env"
    end
  end
end
