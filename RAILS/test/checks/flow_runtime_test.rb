# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require "yaml"
require_relative "../../../MASTER/checks/lib/live/flow_journey"
require_relative "../../../MASTER/checks/lib/live/user_flow"
require_relative "support/flow_coverage_sources"

class FlowRuntimeTest < Minitest::Test
  include FlowCoverageSources

  def test_a_check_whose_apps_are_all_down_names_each_app_and_is_not_green
    result = with_ports_closed do
      with_env("CHECK_REQUIRE_LIVE" => nil, "CHECK_SOURCE_ONLY" => nil, "FLOW_BRGEN_PORT" => nil, "FLOW_AMBER_PORT" => nil,
               "FLOW_BSDPORTS_PORT" => nil, "FLOW_MASTER_PORT" => nil) { Deploy::FlowJourneyCheck.new.run }
    end

    assert_equal :inconclusive, result.outcome
    refute result.conclusive?
    assert_equal FLEET.sort, Deploy::FlowCoverage.down_apps(result).sort,
                 "every declared app is named as skipped:app-down"
    assert(result.warnings.any? { |line| line.include?("skipped:app-down") })
    assert_equal FLOWS.size, result.warnings.grep(/\Asurface0: .* SKIPPED/).size, "each flow reports its own outcome"
  end

  def test_one_app_down_among_running_ones_is_inconclusive_not_passed
    result = Deploy::CheckResult.new
    result.checked!(40)
    with_env("CHECK_SOURCE_ONLY" => nil, "CHECK_REQUIRE_LIVE" => nil) do
      Deploy::FlowCoverage.record_app_down(result, check: "flow_journey", app: "amber", port: 61_352, flows: %w[amber_signup_sign_out_in])
    end

    assert_equal :inconclusive, result.outcome, "forty checks ran and one app did not; the check must not read as a pass"
    assert result.incomplete?
    assert_equal ["amber"], Deploy::FlowCoverage.down_apps(result)
    assert_includes result.gaps.values.first.clause, "waits for the operator"
  end

  def test_a_real_failure_still_outranks_the_skip
    result = Deploy::CheckResult.new
    result.fail("flow:x broke")
    with_env("CHECK_SOURCE_ONLY" => nil, "CHECK_REQUIRE_LIVE" => nil) do
      Deploy::FlowCoverage.record_app_down(result, check: "flow_journey", app: "amber", port: 1, flows: [])
    end

    assert_equal :failed, result.outcome
  end

  def test_source_only_says_so_and_stays_a_pass
    result = Deploy::CheckResult.new
    result.checked!(3)
    with_env("CHECK_SOURCE_ONLY" => "1", "CHECK_REQUIRE_LIVE" => nil) do
      Deploy::FlowCoverage.record_app_down(result, check: "flow_journey", app: "amber", port: 1, flows: %w[a b])
    end

    assert_equal :passed, result.outcome
    refute result.incomplete?
    assert(result.warnings.any? { |line| line.include?("skipped:app-down") }, "still named, only not held against the check")
  end

  def test_require_live_turns_the_skip_into_a_failure
    result = Deploy::CheckResult.new
    with_env("CHECK_REQUIRE_LIVE" => "1", "CHECK_SOURCE_ONLY" => nil) do
      Deploy::FlowCoverage.record_app_down(result, check: "flow_journey", app: "brgen", port: 38_182, flows: %w[x])
    end

    assert_equal :failed, result.outcome
  end

  def test_incomplete_survives_a_merge
    leaf = Deploy::CheckResult.new
    leaf.checked!(2)
    leaf.incomplete!("flow_journey: brgen skipped:app-down")
    composite = Deploy::CheckResult.new.merge!(leaf, label: "layout_suite")

    assert_equal :inconclusive, composite.outcome
  end

  def test_user_flow_records_a_closed_port_instead_of_going_quiet
    check = Deploy::UserFlowCheck.new
    result = Deploy::CheckResult.new
    check.instance_variable_set(:@result, result)
    app = Struct.new(:name, :port).new("amber", 61_352)
    with_env("CHECK_REQUIRE_LIVE" => nil, "CHECK_SOURCE_ONLY" => nil, "FLOW_AMBER_PORT" => nil) do
      with_ports_closed { check.send(:live_flow_checks, app) }
    end

    assert result.incomplete?
    assert_equal ["amber"], Deploy::FlowCoverage.down_apps(result)
    assert_equal 0, result.checks_ran, "a skipped step is not a check that ran"
  end

  def test_flow_port_override_points_one_app_at_a_spare_port
    assert_equal 38_900, Deploy::FlowCoverage.port_for("brgen", 38_182, { "FLOW_BRGEN_PORT" => "38900" })
    assert_equal 38_182, Deploy::FlowCoverage.port_for("brgen", 38_182, {})
    assert_equal 38_182, Deploy::FlowCoverage.port_for("brgen", 38_182, { "FLOW_BRGEN_PORT" => "x" })
  end

  # --- the vocabulary -----------------------------------------------------------

  def test_a_captured_string_and_number_feed_later_steps_and_assertions
    check = check_with_result
    captures = {}
    vars = { "unique" => "abc" }
    step = { "capture" => [{ "pattern" => 'href="(/posts/[a-z0-9-]+)"', "as" => "post" }],
             "number" => [{ "pattern" => 'score">\s*(-?\d+)', "as" => "score" }] }

    assert check.send(:check_step, "f/s", step, response(%(<a href="/posts/mitt-abc">x</a><i class="score"> -3</i>)), captures, vars)
    assert_equal "/posts/mitt-abc", vars["post"]
    assert_equal(-3, captures["score"])
    assert_equal "/posts/mitt-abc/vote", check.send(:interpolate, "$post/vote", vars)
  end

  def test_a_capture_that_finds_nothing_fails_the_step_unless_optional
    check = check_with_result
    refute check.send(:check_step, "f/s", { "capture" => [{ "pattern" => "(zzz)", "as" => "x" }] }, response("nope"), {}, {})
    refute_empty check_failures(check)

    check = check_with_result
    assert check.send(:check_step, "f/s", { "capture" => [{ "pattern" => "(zzz)", "as" => "x", "optional" => true }] }, response("nope"), {}, {})
  end

  def test_delta_shifts_the_right_hand_side_so_a_vote_can_be_one_more
    flow = { "id" => "v", "assert" => [{ "left" => "after", "op" => "==", "right" => "before", "delta" => 1 }] }
    check = check_with_result
    check.send(:check_assertions, flow, { "before" => 4, "after" => 5 })
    assert_empty check_failures(check)

    check = check_with_result
    check.send(:check_assertions, flow, { "before" => 4, "after" => 4 })
    assert_equal 1, check_failures(check).size
  end

  def test_final_path_can_be_matched_or_forbidden_by_pattern
    check = check_with_result
    assert check.send(:check_step, "f/s", { "expect_final_path" => { "matches" => "^/posts/" } }, response("ok", path: "/posts/x"), {}, {})
    refute check.send(:check_step, "f/s", { "expect_final_path" => { "not_matches" => "^/posts/" } }, response("ok", path: "/posts/x"), {}, {})
  end

  def test_the_apps_own_rate_limit_is_named_not_mistaken_for_success
    check = check_with_result

    refute check.send(:check_step, "f/sign_up", {}, response("<p>Prøv igjen senere.</p>"), {}, {})
    assert_match(/rate limited/, check_failures(check).first)
  end

  def test_an_asset_step_may_contain_the_word_exception
    assert check_with_result.send(:check_step, "f/sw", { "asset" => true }, response("throw new Exception('workbox')"), {}, {})
    page = check_with_result
    page.send(:check_step, "f/page", {}, response("<h1>Exception</h1>"), {}, {})
    assert_match(/contains Exception/, check_failures(page).first)
  end

  def test_a_mail_step_reads_the_newest_message_and_decodes_quoted_printable
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "a@example.test"), <<~MAIL)
        Date: Mon, 1 Jan 2026 00:00:00 +0000
        Content-Transfer-Encoding: quoted-printable

        http://localhost:3000/verify/OLD0LD0LD0LD0LD0LD0LD0

        Date: Mon, 1 Jan 2026 00:05:00 +0000
        Content-Transfer-Encoding: quoted-printable

        http://localhost:3000/verify/NEWTOKEN1234567=
        89abc and html http://x/verify/OTHER00000000000000
      MAIL
      with_env("FLOW_BRGEN_MAIL_DIR" => dir) do
        vars = {}
        spec = { "to" => "a@example.test", "within" => 0.1, "capture" => [{ "pattern" => 'verify/([A-Za-z0-9_-]{16,})', "as" => "token" }] }

        assert_equal :read, check_with_result.send(:read_mail, "f/mail", spec, "brgen", vars)
        assert_equal "NEWTOKEN123456789abc", vars["token"]
      end
    end
  end

  def test_a_missing_mail_file_is_inconclusive_not_a_verdict_on_the_product
    Dir.mktmpdir do |dir|
      with_env("FLOW_AMBER_MAIL_DIR" => dir) do
        check = check_with_result
        outcome = check.send(:read_mail, "f/mail", { "to" => "nobody@example.test", "within" => 0.1, "capture" => [] }, "amber", {})

        assert_equal :inconclusive, outcome
        assert_empty check_failures(check)
        assert_equal 1, check.instance_variable_get(:@result).unchecked.size
      end
    end
  end

  def test_a_step_that_needs_a_value_the_page_did_not_have_is_inconclusive
    check = check_with_result
    flow = { "id" => "needs", "steps" => [{ "name" => "act", "post" => "/likes?user_id=$person", "needs" => ["person"] }] }
    client = Object.new
    def client.accept=(_value); end
    klass = Deploy::FlowJourneyCheck::FlowClient
    klass.singleton_class.send(:alias_method, :real_new, :new)
    klass.define_singleton_method(:new) { |**| client }
    begin
      assert_equal :inconclusive, check.send(:run_flow, flow, 1, "brgen")
    ensure
      klass.singleton_class.send(:alias_method, :new, :real_new)
      klass.singleton_class.send(:remove_method, :real_new)
    end
    assert_empty check_failures(check)
    assert_includes check.instance_variable_get(:@result).unchecked.first, "dataset is empty"
  end

  private
end
