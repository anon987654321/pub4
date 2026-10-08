# frozen_string_literal: true

require_relative "test_helper"
require_relative "support_master_container"

# Smoke tests for the with_master_container helper itself.
class TestMasterContainer < Minitest::Test
  include Master::TestSupport::Container

  def test_boots_full_infra_stack
    with_master_container do |m|
      assert m[:gateway],     "expected :gateway"
      assert m[:pipeline],    "expected :pipeline"
      assert m[:bus],         "expected :bus"
      assert m[:memory],      "expected :memory"
      assert m[:trace],       "expected :trace"
      assert m[:personality], "expected :personality"
    end
  end

  def test_help_command_round_trips
    with_master_container do |m|
      result = m[:gateway].receive(channel: :cli, message: "/help")
      assert result.ok?, "gateway should accept /help"
    end
  end

  def test_trace_records_turn
    with_master_container do |m|
      m[:gateway].receive(channel: :cli, message: "/help")
      pretty = m[:trace].pretty_last
      assert_match(/turn /, pretty)
      assert_match(/gateway:turn_done/, pretty)
    end
  end

  def test_typed_memory_persists_within_container
    with_master_container do |m|
      m[:memory].remember("role", "architect", type: "user")
      assert_operator m[:memory].type_counts.fetch("user", 0), :>=, 1
    end
  end
end
