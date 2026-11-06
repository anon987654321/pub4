# frozen_string_literal: true

require "tempfile"
require_relative "test_helper"

class TestSubscriptionAuth < Minitest::Test
  Status = Struct.new(:ok) do
    def success? = ok
    def exitstatus = ok ? 0 : 1
  end

  def test_profiles_are_subscription_only
    profiles = Master::Ground::SubscriptionAuth.profiles
    refute_empty profiles
    assert profiles.all? { |lane| lane["auth"] == "subscription" }
  end

  def test_find_accepts_public_provider_name
    lane = Master::Ground::SubscriptionAuth.find("claude")
    assert_equal "claude", lane["name"] if lane
  end

  def test_unknown_provider_is_safe
    assert_match(/unknown subscription/, Master::Ground::SubscriptionAuth.login("does-not-exist"))
  end

  def test_codex_and_grok_offer_device_code_login_without_changing_desktop_defaults
    %w[chatgpt grok].each do |name|
      lane = Master::Ground::SubscriptionAuth.find(name)
      assert_equal ["login"], lane.fetch("login_args")
      assert_equal ["login", "--device-auth"], lane.fetch("device_login_args")
      assert_equal lane.fetch("device_login_args"),
                   Master::Ground::SubscriptionAuth.login_arguments(lane, device_auth: true)
    end
  end

  def test_mobile_prefers_device_code_when_provider_supports_it
    lane = Master::Ground::SubscriptionAuth.find("chatgpt")
    Master::Ground::SubscriptionAuth.stub(:device_auth_preferred?, true) do
      assert_equal ["login", "--device-auth"],
                   Master::Ground::SubscriptionAuth.login_arguments(lane, device_auth: nil)
    end
  end

  def test_provider_without_device_flow_keeps_browser_login
    lane = Master::Ground::SubscriptionAuth.find("claude")
    assert_equal ["auth", "login"],
                 Master::Ground::SubscriptionAuth.login_arguments(lane, device_auth: nil)
    assert_match(/no device-code login/,
                 Master::Ground::SubscriptionAuth.login("claude", device_auth: true))
  end

  def test_status_requires_a_configured_match_and_rejects_refusal_text
    lane = { "command" => "codex", "status_match" => "Logged in" }
    Master::Ground::SubscriptionAuth.stub(:cli_binary, "codex") do
      Master::Io::Exec.stub(:capture2e, ["Not logged in", Status.new(true)]) do
        refute Master::Ground::SubscriptionAuth.command_ok?(lane, ["login", "status"])
      end
    end
  end

  def test_interactive_login_runner_returns_the_child_exit_status
    status = Master::Ground::SubscriptionAuth.run_interactive(RbConfig.ruby, "-e", "exit 0")
    assert_predicate status, :success?
  end

  def test_interactive_login_runner_kills_a_timed_out_child
    assert_raises(Master::Ground::SubscriptionAuth::LoginTimeout) do
      Master::Ground::SubscriptionAuth.run_interactive(RbConfig.ruby, "-e", "sleep 5", timeout: 0.05)
    end
  end

  def test_auth_dispatch_accepts_explicit_device_code_mode
    require_relative "../lib/cli/command_registry"
    observed = nil
    handler = ->(name, device_auth: nil) { observed = [name, device_auth]; "started" }
    Master::Ground::SubscriptionAuth.stub(:login, handler) do
      assert_equal "started", Master::CLI::CommandRegistry.dispatch_auth(ctx: { args: "login chatgpt --device-auth" })
    end
    assert_equal ["chatgpt", true], observed
  end
end
