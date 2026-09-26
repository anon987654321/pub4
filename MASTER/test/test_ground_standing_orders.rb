# frozen_string_literal: true

require_relative "test_helper"
require "fileutils"

# TODO.md, Test coverage: no test named StandingOrders. This is the runtime's
# autonomous scheduler — it decides, unattended, which commands run and how often,
# including event-triggered ones with regex filters. Nothing pinned any of it.
#
# STATE_PATH is a constant under the real .master/, so the file is saved and put
# back: a test must not silently reset the operator's live order state.
class StandingOrdersTest < Minitest::Test
  Orders = Master::Ground::StandingOrders

  KEPT = [Orders::STATE_PATH, Master::Ground::Tool::Domain::CONSENT_PATH].freeze

  def setup
    @state_path = Orders::STATE_PATH
    @saved = KEPT.to_h { |path| [path, File.file?(path) ? File.binread(path) : nil] }
    @orders = Orders.new
  end

  def teardown
    @saved.each do |path, bytes|
      if bytes
        FileUtils.mkdir_p(File.dirname(path))
        File.binwrite(path, bytes)
      elsif File.file?(path)
        File.delete(path)
      end
    end
  end

  def order(overrides = {})
    {
      "name" => "test_order", "description" => "d", "trigger" => "scheduled",
      "interval_s" => 60, "command" => "noop", "enabled" => true,
      "state" => "pending", "last_run_at" => 0
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

  def test_due_can_be_scoped_to_one_owner
    mine = order("name" => "mine", "owner" => "owner123")
    theirs = order("name" => "theirs", "owner" => "operator")

    with_orders([mine, theirs]) do
      assert_equal ["mine"], @orders.due(owner: "owner123").map { |o| o["name"] }
      assert_equal ["mine", "theirs"], @orders.due.map { |o| o["name"] }
    end
  end

  # An errored order waits for /orders reset, and "running" must not be picked up
  # twice.
  def test_due_skips_running_and_errored_orders
    with_orders([order("name" => "running", "state" => "running"),
                 order("name" => "errored", "state" => "error"),
                 order("name" => "done", "state" => "done")]) do
      assert_equal %w[done], @orders.due.map { |o| o["name"] }
    end
  end

  # A process that died mid-run left "running" on disk. The next boot must say
  # the run did not finish, rather than leave it running forever or call it done.
  def test_a_run_interrupted_by_a_restart_is_reported_not_left_running
    carried = { "test_order" => { "state" => "running", "last_run_at" => 7 },
                "idle" => { "state" => "done", "last_run_at" => 7 } }

    @orders.stub(:read_defs, [order, order("name" => "idle")]) do
      @orders.stub(:read_state, carried) do
        restored = @orders.send(:load_orders)

        assert_equal "error", restored.first["state"]
        assert_match(/interrupted/, restored.first["last_error"])
        assert_equal "done", restored.last["state"], "only a carried running state is an interruption"
      end
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

  # /orders run executes whatever is due with nobody watching, so a hard reset,
  # a push or doas written as an order must never reach the router.
  def test_run_due_refuses_destructive_commands_before_routing
    routed = []
    pipeline = ->(input) { routed << input.value![:user_message]; Master::Result.ok("ran") }
    orders = Orders.new(pipeline:)
    list = ["git reset --hard origin/main", "git push origin main", "doas rcctl stop master", "scan"]
             .each_with_index.map { |cmd, i| order("name" => "o#{i}", "command" => cmd) }
    orders.instance_variable_set(:@orders, list)

    results = orders.run_due!

    assert_equal %w[scan], routed
    refused = results.reject { |r| r[:result].ok? }.map { |r| r[:name] }
    assert_equal %w[o0 o1 o2], refused
    assert_match(/standing order refused/, results.first[:result].message)
    assert_equal "error", list.first["state"]
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

  # An objective is an order with an owner, a domain, a wake and a verify, and
  # it is still there, with what it has shown, after the process that set it
  # has gone.
  def objective(**fields)
    { name: "deploy_window", command: nil, domain: "coding", trigger: "heartbeat", interval_s: 0,
      verify: "echo window-open", owner: "johann" }.merge(fields)
  end

  def test_an_objective_added_at_runtime_survives_a_restart_with_its_evidence
    with_orders([]) do
      @orders.upsert(**objective)
      @orders.run_due!
    end

    restored = Orders.new.instance_variable_get(:@orders).find { |o| o["name"] == "deploy_window" }
    assert_equal %w[johann coding heartbeat], restored.values_at("owner", "domain", "trigger")
    assert_equal "verified", restored["state"]
    assert_equal "window-open", restored["evidence"].last["output"], "the check's own output is the evidence"
  end

  def test_the_heartbeat_wakes_an_objective_and_a_passing_verify_meets_it
    bus = Master::Trace::EventBus.new
    orders = Orders.new(event_bus: bus)
    orders.instance_variable_set(:@orders, [])
    orders.upsert(**objective)

    bus.publish("heartbeat:tick")

    met = orders.instance_variable_get(:@orders).first
    assert_equal "verified", met["state"]
    assert_empty orders.due, "a met objective stops waking"
  end

  def test_a_failing_verify_leaves_the_objective_waking_with_the_failure_on_record
    with_orders([]) do
      @orders.upsert(**objective(verify: "ruby -e exit(3)"))
      @orders.run_due!
      pending = @orders.instance_variable_get(:@orders).first

      assert_equal "done", pending["state"]
      refute pending["evidence"].last["ok"]
      assert_equal %w[deploy_window], @orders.due.map { |o| o["name"] }
    end
  end

  def test_finance_is_off_until_the_operator_consents
    FileUtils.rm_f(Master::Ground::Tool::Domain::CONSENT_PATH)
    with_orders([]) do
      @orders.upsert(**objective(domain: "finance"))
      @orders.run_due!
      refused = @orders.instance_variable_get(:@orders).first
      assert_equal "done", refused["state"]
      assert_match(/finance is off until the operator consents/, refused["evidence"].last["output"])

      Master::Ground::Tool::Domain.grant("finance")
      refused["last_run_at"] = 0
      @orders.run_due!
      assert_equal "verified", refused["state"]
    end
  end

  def test_a_consented_finance_objective_still_cannot_reach_the_coding_tools
    Master::Ground::Tool::Domain.grant("finance")
    routed = []
    orders = Orders.new(container: { commands: {}, memory: :shared_store })
    orders.instance_variable_set(:@orders, [])
    Master::CLI::TurnRouter.stub(:call, ->(**kw) { routed << kw }) do
      orders.upsert(**objective(domain: "finance", command: "write the budget", verify: nil, trigger: "scheduled"))
      result = orders.run_due!.first[:result]

      assert_empty routed
      assert_match(/finance cannot reach commands/, result.message)
    end
  end

  def test_a_domain_container_withholds_what_the_domain_does_not_reach
    full = { commands: :registry, agent: :agent, memory: :store, bus: :bus }
    Master::Ground::Tool::Domain.grant("household")

    assert_equal({ bus: :bus, domain: "household" }, Master::Ground::Tool::Domain.container("household", full))
    assert_equal full.merge(domain: "coding"), Master::Ground::Tool::Domain.container("coding", full)
  end
  def test_orders_add_reads_fields_whose_values_keep_their_spaces
    saved = []
    standing = Object.new.tap { |o| o.define_singleton_method(:upsert) { |**kw| saved << kw } }
    Master::CLI::CommandRegistry.add_order(standing, "name=tests domain=coding wake=heartbeat verify=env RAILS_ENV=test bundle exec rake test")

    assert_equal({ name: "tests", domain: "coding", trigger: "heartbeat", verify: "env RAILS_ENV=test bundle exec rake test", owner: "operator" },
                 saved.first)
    assert_match(/usage/, Master::CLI::CommandRegistry.add_order(standing, "domain=coding verify=true"))
  end
end
