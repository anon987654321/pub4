# frozen_string_literal: true

require "test_helper"
require_relative "../lib/fix/model_roles"

class TestFixModelRoles < Minitest::Test
  Roles = Master::Fix::ModelRoles
  CFG = {
    "roles" => {
      "critic" => %w[agy:auto grok-cli:auto claude-cli:claude-sonnet-5-5],
      "fixer" => %w[claude-cli:claude-opus-5-5 claude-cli:claude-sonnet-5-5],
      "wisher" => %w[grok-cli:auto],
    },
    "dead" => %w[gemini],
  }.freeze

  def assign(alive: ->(_) { true }, env: {}, cfg: CFG) = Roles.assign(env:, alive:, cfg:)

  def test_critic_is_another_provider_than_the_fixer
    roles = assign

    assert_equal "claude-cli:claude-opus-5-5", roles.fixer
    assert_equal "agy:auto", roles.critic
    refute roles.shared?
  end

  def test_dead_lane_is_skipped
    roles = assign(alive: ->(id) { !id.start_with?("agy") })

    assert_equal "grok-cli:auto", roles.critic
  end

  def test_same_lane_other_model_beats_sharing
    roles = assign(alive: ->(id) { id.start_with?("claude-cli") })

    assert_equal "claude-cli:claude-sonnet-5-5", roles.critic
    refute roles.shared?
  end

  def test_no_alternative_shares_the_fixer
    cfg = CFG.merge("roles" => CFG["roles"].merge("critic" => %w[claude-cli:claude-opus-5-5]))
    roles = assign(cfg:)

    assert roles.shared?
  end

  def test_env_overrides_win
    roles = assign(env: { "MASTER_FIX_CRITIC_MODEL" => "x:c", "MASTER_FIX_FIXER_MODEL" => "y:f" })

    assert_equal %w[x:c y:f], [roles.critic, roles.fixer]
  end

  def test_dead_prefix_from_config_is_never_chosen
    cfg = CFG.merge("roles" => CFG["roles"].merge("critic" => %w[gemini-2.5-flash grok-cli:auto]))

    assert_equal "grok-cli:auto", assign(cfg:).critic
  end

  def test_announce_logs_the_shared_notice
    out = StringIO.new
    Master::Trace::Dmesg.stub(:status, ->(unit, msg, **) { out << "#{unit}: #{msg}\n" }) do
      Roles.announce(Roles::Assignment.new(critic: "m:1", fixer: "m:1", wisher: nil))
    end

    assert_includes out.string, "roles0: critic and fixer share m:1 (no alternative alive)"
  end

  def test_pinned_sets_the_dispatcher_pin_only_inside_the_block
    pin = Master::Review::LLMDispatcher::ModelPin
    seen = nil
    Roles.stub(:current, Roles::Assignment.new(critic: "m:c", fixer: "m:f", wisher: nil)) do
      Roles.pinned(:critic) { seen = pin.current }
      assert_nil Roles.pinned(:fixer, only: false) { pin.current }
    end

    assert_equal "m:c", seen
    assert_nil pin.current
  end
end
