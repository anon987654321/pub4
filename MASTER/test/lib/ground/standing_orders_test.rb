# frozen_string_literal: true

require_relative "../../test_helper"
require "fileutils"

# DEBT.md, Test coverage: no test named StandingOrders. This is the runtime's
# autonomous scheduler — it decides, unattended, which commands run and how often,
# including event-triggered ones with regex filters. Nothing pinned any of it.
#
# STATE_PATH is a constant under the real .master/, so the file is saved and put
# back: a test must not silently reset the operator's live order state.
class StandingOrdersTest < Minitest::Test
  Orders = Master::Ground::StandingOrders

  def setup
    @state_path = Orders::STATE_PATH
    @saved = File.file?(@state_path) ? File.binread(@state_path) : nil
    @orders = Orders.new
  end

  def teardown
    if @saved
      FileUtils.mkdir_p(File.dirname(@state_path))
      File.binwrite(@state_path, @saved)
    elsif File.file?(@state_path)
      File.delete(@state_path)
    end
  end

  def order(overrides = {})
    {
      "name" => "test_order", "description" => "d", "trigger" => "scheduled",
      "interval_s" => 60, "command" => "noop", "enabled" => true,
      "state" => "pending", "last_run_at" => 0,
    }.merge(overrides)
  end

  def with_orders(list)
    previous = @orders.instance_variable_get(:@orders)
    @orders.instance_variable_set(:@orders, list)
    yield
  ensure
    @orders.instance_variable_set(:@orders, previous)
  end

  def test_state_of_falls_back_for_an_unknown_state
    assert_equal "pending", @orders.send(:state_of, order)
    assert_equal "done", @orders.send(:state_of, order("state" => "nonsense"))
    assert_equal "done", @orders.send(:state_of, order("state" => nil))
    Orders::VALID_STATES.each { |state| assert_equal state, @orders.send(:state_of, order("state" => state)) }
  end

  def test_due_requires_enabled_scheduled_and_an_elapsed_interval
    stale = order("name" => "stale", "last_run_at" => Time.now.to_i - 120)
    fresh = order("name" => "fresh", "last_run_at" => Time.now.to_i)
    disabled = order("name" => "off", "enabled" => false, "last_run_at" => 0)
    evented = order("name" => "evented", "trigger" => "event", "last_run_at" => 0)

    with_orders([stale, fresh, disabled, evented]) do
      assert_equal %w[stale], @orders.due.map { |o| o["name"] }
    end
  end

  # A previous failure must not park an order forever — but "running" must not be
  # picked up twice either.
  def test_due_skips_running_and_errored_orders
    with_orders([order("name" => "running", "state" => "running"),
                 order("name" => "errored", "state" => "error"),
                 order("name" => "done", "state" => "done")]) do
      assert_equal %w[done], @orders.due.map { |o| o["name"] }
    end
  end

  def test_upsert_creates_then_updates_in_place
    with_orders([]) do
      @orders.upsert(name: "nightly", description: "first", command: "scan")
      list = @orders.instance_variable_get(:@orders)

      assert_equal 1, list.size
      assert_equal "pending", list.first["state"]

      @orders.upsert(name: "nightly", description: "second", command: "scan", interval_s: 7200)

      assert_equal 1, @orders.instance_variable_get(:@orders).size
      assert_equal "second", @orders.instance_variable_get(:@orders).first["description"]
      assert_equal 7200, @orders.instance_variable_get(:@orders).first["interval_s"]
    end
  end

  def test_enable_disable_and_reset_report_a_missing_order
    with_orders([]) do
      assert_equal "no order named 'ghost'", @orders.enable("ghost")
      assert_equal "no order named 'ghost'", @orders.disable("ghost")
      assert_equal "no order named 'ghost'", @orders.reset("ghost")
    end
  end

  def test_reset_clears_state_and_the_last_error
    subject = order("state" => "error", "last_error" => "boom")
    with_orders([subject]) do
      assert_match(/reset/, @orders.reset("test_order"))
      assert_equal "pending", subject["state"]
      refute subject.key?("last_error")
    end
  end

  def test_toggle_flips_enabled
    subject = order
    with_orders([subject]) do
      @orders.disable("test_order")
      refute subject["enabled"]
      @orders.enable("test_order")
      assert subject["enabled"]
    end
  end

  def test_list_and_format_describe_state_flag_and_error
    subject = order("enabled" => false, "state" => "error", "last_error" => "x" * 80,
                    "last_run_at" => Time.new(2026, 1, 2).to_i)
    with_orders([subject]) do
      line = @orders.list

      assert_includes line, "off|error"
      assert_includes line, "2026-01-02"
      assert_includes line, "!!"
      assert_equal 60, line[/!! (x+)/, 1].length, "the error is truncated for display"
    end
  end

  def test_list_says_so_when_empty
    with_orders([]) { assert_equal "no standing orders defined", @orders.list }
  end

  def test_event_match_needs_enabled_event_trigger_and_the_right_name
    evented = order("trigger" => "event", "event" => "tool:after")

    assert @orders.send(:event_match?, evented, "tool:after", {})
    refute @orders.send(:event_match?, evented, "tool:before", {})
    refute @orders.send(:event_match?, order("event" => "tool:after"), "tool:after", {})
    refute @orders.send(:event_match?, evented.merge("enabled" => false), "tool:after", {})
  end

  def test_filter_and_exclude_are_regexes_over_the_payload
    subject = order("trigger" => "event", "event" => "tool:after", "filter" => "write_file")

    assert @orders.send(:event_match?, subject, "tool:after", { tool: "write_file" })
    refute @orders.send(:event_match?, subject, "tool:after", { tool: "read_file" })

    excluded = subject.merge("exclude" => "spec/")
    refute @orders.send(:event_match?, excluded, "tool:after", { tool: "write_file", path: "spec/x.rb" })
    assert @orders.send(:event_match?, excluded, "tool:after", { tool: "write_file", path: "lib/x.rb" })
  end

  def test_an_empty_filter_matches_everything
    assert @orders.send(:filter_match?, order, {})
    refute @orders.send(:exclude_match?, order, {})
  end

  def test_debounce_blocks_a_rerun_inside_the_window
    assert @orders.send(:debounced?, order("last_run_at" => Time.now.to_i))
    refute @orders.send(:debounced?, order("last_run_at" => Time.now.to_i - Orders::DEBOUNCE_S - 1))
    refute @orders.send(:debounced?, order("last_run_at" => 0)), "never-run orders are not debounced"
  end

  def test_an_unknown_callable_is_an_error_not_an_exception
    result = @orders.send(:execute_order, order("callable" => "no_such_order"))

    refute result.ok?
    assert_match(/unknown callable/, result.message)
  end

  def test_without_a_router_or_pipeline_execution_reports_no_router
    result = @orders.send(:execute_order, order)

    refute result.ok?
    assert_match(/no router/, result.message)
  end

  def test_persist_writes_only_the_state_keys
    with_orders([order("state" => "done", "last_run_at" => 42, "last_error" => "e")]) do
      @orders.send(:persist)
      written = YAML.safe_load_file(@state_path)

      assert_equal %w[last_error last_run_at state], written.fetch("test_order").keys.sort
      assert_equal 42, written.dig("test_order", "last_run_at")
    end
  end

  def test_builtin_intervals_match_the_declared_constants
    assert_equal 86_400, Orders::DAILY_INTERVAL
    assert_equal 604_800, Orders::WEEKLY_INTERVAL
    intervals = Orders::BUILTIN_ORDERS.map { |o| o[:interval_s] }

    assert_includes intervals, Orders::DAILY_INTERVAL
    assert_includes intervals, Orders::WEEKLY_INTERVAL
  end
end
