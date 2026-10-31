# frozen_string_literal: true

require "test_helper"
require_relative "../lib/fix/governor"

class GovernorTest < Minitest::Test
  Config = Struct.new(:auto?)

  def test_guarded_tool_uses_the_interactive_session_asker
    Fiber[:master_terminal_ask] = ->(prompt:, options:) { "approve" }
    governor = Master::Fix::Governor.new(config: Config.new(false))

    result = governor.check_permit("web_fetch", :guarded, "https://example.com")

    assert result.ok?
  ensure
    Fiber[:master_terminal_ask] = nil
  end

  def test_invalid_terminal_choice_is_a_validation_error
    Fiber[:master_terminal_ask] = ->(prompt:, options:) { "garbage" }
    governor = Master::Fix::Governor.new(config: Config.new(false))

    result = governor.check_permit("web_fetch", :guarded, "https://example.com")

    refute result.ok?
    assert_equal :validation, result.category
  ensure
    Fiber[:master_terminal_ask] = nil
  end

  # The /fix research pass reads protocol-declared sources with no terminal to ask.
  def test_a_protocol_read_passes_the_guarded_tier_and_nothing_else
    governor = Master::Fix::Governor.new(config: Config.new(false))
    Fiber[:master_protocol_read] = true

    assert governor.check_permit("web_fetch", :guarded, "https://github.com/rubocop/ruby-style-guide").ok?
    refute governor.check_permit("shell", :dangerous, "doas reboot").ok?
  ensure
    Fiber[:master_protocol_read] = nil
  end

  def test_the_rate_ceiling_comes_from_the_data_and_is_not_three_a_minute
    assert_operator Master::Fix::Governor.rate_limits.fetch("dangerous"), :>, 10
  end

  def test_a_call_over_the_ceiling_is_refused
    governor = Master::Fix::Governor.new(config: Config.new(true))

    Master::Fix::Governor.stub(:rate_limits, { "dangerous" => 2 }) do
      results = Array.new(3) { governor.check_permit("zsh", :dangerous, "ls") }

      assert_equal %i[ok ok rate_limit], results.map { |result| result.ok? ? :ok : result.category }
    end
  end

  # The @auto hole this closes: an unattended run used to get ok for the whole
  # dangerous tier, including a description that asks for root.
  def test_an_escalation_description_never_rides_the_auto_gate
    governor = Master::Fix::Governor.new(config: Config.new(true))

    Master::Fix::Governor.stub(:auto_allowlist, ["shell"]) do
      Master::Fix::Governor.stub(:auto_dangerous_budget, 5) do
        result = governor.check_permit("shell", :dangerous, "doas reboot")

        refute result.ok?
        assert_equal :validation, result.category
      end
    end
  end

  def test_an_exhausted_budget_fails_closed_in_an_unattended_run
    governor = Master::Fix::Governor.new(config: Config.new(true))

    Master::Fix::Governor.stub(:auto_allowlist, []) do
      Master::Fix::Governor.stub(:auto_dangerous_budget, 1) do
        assert governor.check_permit("zsh", :dangerous, "ls").ok?
        refute governor.check_permit("zsh", :dangerous, "ls -la").ok?
        refute governor.check_permit("zsh", :dangerous, "ls -R").ok?
      end
    end
  end

  def test_a_persistent_allowlist_entry_spends_no_budget
    governor = Master::Fix::Governor.new(config: Config.new(true))

    Master::Fix::Governor.stub(:auto_allowlist, ["zsh"]) do
      Master::Fix::Governor.stub(:auto_dangerous_budget, 1) do
        assert governor.check_permit("zsh", :dangerous, "ls").ok?
        assert governor.check_permit("zsh", :dangerous, "ls").ok?, "allowlisted tools are not budget-limited"
        assert governor.check_permit("shell", :dangerous, "ls").ok?, "one budgeted approval remains"
        refute governor.check_permit("shell", :dangerous, "ls -la").ok?
      end
    end
  end

  def test_each_budget_spend_is_published_for_the_trace
    bus = FakeBus.new
    governor = Master::Fix::Governor.new(config: Config.new(true), event_bus: bus)

    Master::Fix::Governor.stub(:auto_allowlist, []) do
      Master::Fix::Governor.stub(:auto_dangerous_budget, 2) do
        governor.check_permit("zsh", :dangerous, "ls")
        governor.check_permit("zsh", :dangerous, "ls")
      end
    end

    spends = bus.events.select { |event| event.first == "tool:auto_dangerous" }
    assert_equal [1, 0], spends.map { |_name, payload| payload[:budget_left] }
  end

  # A remembered "always allow" was given by a human for one exact request, so it
  # outranks the budget; a denial is still honored first.
  def test_a_remembered_decision_outranks_the_budget
    governor = Master::Fix::Governor.new(config: Config.new(true))

    Master::Fix::Governor.stub(:auto_allowlist, []) do
      Master::Fix::Governor.stub(:auto_dangerous_budget, 0) do
        governor.allow!("zsh", "ls")
        assert governor.check_permit("zsh", :dangerous, "ls").ok?

        governor.deny!("shell", "ls")
        refute governor.check_permit("shell", :dangerous, "ls").ok?
      end
    end
  end

  # Interactive mode is unchanged: an ordinary dangerous description auto-approves
  # inside the rate ceiling, and an escalation-shaped one asks.
  def test_interactive_mode_keeps_its_old_dangerous_tier_shape
    governor = Master::Fix::Governor.new(config: Config.new(false))

    Master::Fix::Governor.stub(:auto_allowlist, []) do
      Master::Fix::Governor.stub(:auto_dangerous_budget, 0) do
        assert governor.check_permit("zsh", :dangerous, "ls").ok?
        refute governor.check_permit("zsh", :dangerous, "sudo ls").ok?
      end
    end
  end

  class FakeBus
    attr_reader :events

    def initialize = @events = []
    def publish(name, payload = nil, **kwargs) = @events << [name, payload || kwargs]
  end
end
