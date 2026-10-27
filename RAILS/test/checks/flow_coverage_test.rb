# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require "yaml"
require_relative "../../../MASTER/checks/lib/live/flow_journey"
require_relative "../../../MASTER/checks/lib/live/user_flow"

# The operator asked why the last /fix exercised only the amber email and user
# flows and nothing of brgen and its verticals. Two causes, both pinned here.
#
# 1. A flow check that finds an app's port closed filed one warning and carried
#    on, so the check printed PASSED over journeys that never ran. A skipped app
#    is a named outcome now (skipped:app-down) and the check is :inconclusive.
# 2. flows.yml was 26 flows, 23 of them reads. Nothing signed up, voted, posted,
#    commented, sent a message, listed an item or ordered food; the three that
#    did want credentials nobody exported. The contract below keeps every
#    declared app, and every brgen vertical that a guest can write to, covered
#    by a journey that changes state.
class FlowCoverageTest < Minitest::Test
  ROOT = File.expand_path("../../..", __dir__)
  FLOWS = YAML.safe_load_file(File.join(ROOT, "MASTER", "checks", "data", "flows.yml")).fetch("flows")
  APPS = YAML.safe_load_file(File.join(ROOT, "RAILS", "apps.yml")).fetch("apps").keys + ["master"]

  STEP_KEYS = %w[
    name get post host params expect_status expect_final_path expect_body expect_any forbid_body
    count number capture capture_final_path needs mail accept asset
  ].freeze
  FLOW_KEYS = %w[id app host description requires_data requires_credentials mutates steps assert].freeze

  def writes?(flow) = flow["steps"].any? { |step| step.key?("post") }

  # --- the data ---------------------------------------------------------------

  def test_every_flow_has_the_shape_the_check_reads
    ids = FLOWS.map { |flow| flow["id"] }
    assert_equal ids.uniq, ids, "flow ids must be unique"
    FLOWS.each do |flow|
      assert_empty flow.keys - FLOW_KEYS, "#{flow["id"]}: unknown flow key"
      assert_includes APPS, flow["app"], "#{flow["id"]}: app is not in RAILS/apps.yml"
      refute_empty Array(flow["steps"]), "#{flow["id"]}: no steps"
      flow["steps"].each do |step|
        label = "#{flow["id"]}/#{step["name"]}"
        assert_empty step.keys - STEP_KEYS, "#{label}: unknown step key"
        assert_equal 1, (step.keys & %w[get post mail]).size, "#{label}: exactly one of get/post/mail"
        assert step["name"], "#{label}: a step needs a name so a failure can say which"
        Array(step["expect_status"]).each { |code| assert_kind_of Integer, code, "#{label}: expect_status holds integers" }
      end
    end
  end

  # A $name in a path, a parameter or a pattern must have been produced by an
  # earlier step (capture, capture_final_path, a mail capture), be one of the
  # per-run values FlowJourney binds ($unique and the throwaway passwords), or be
  # a credential the flow declares. Otherwise the request goes out with the
  # literal "$name" and the failure reads as a broken page.
  RUN_BOUND = %w[unique flow_password flow_wrong_password flow_new_password].freeze

  def test_every_placeholder_is_bound_before_it_is_used
    FLOWS.each do |flow|
      bound = RUN_BOUND + Array(flow["requires_credentials"])
      flow["steps"].each do |step|
        label = "#{flow["id"]}/#{step["name"]}"
        used = strings_in(step.reject { |key, _| %w[capture number count mail needs].include?(key) })
        used += strings_in(step["mail"]["to"]) if step["mail"]
        used += Array(step["capture"]).flat_map { |c| strings_in(c["pattern"]) }
        used += Array(step["number"]).flat_map { |c| strings_in(c["pattern"]) }
        used += strings_in(step["count"]["pattern"]) if step["count"]
        used.flat_map { |text| text.scan(/\$([A-Za-z_]\w*)/).flatten }.each do |name|
          assert_includes bound, name, "#{label}: $#{name} is used before any step binds it"
        end
        Array(step["needs"]).each { |name| assert_includes bound, name.to_s, "#{label}: needs #{name} which nothing captured" }
        bound += Array(step["capture"]).map { |c| c["as"].to_s }
        bound += Array(step["mail"] && step["mail"]["capture"]).map { |c| c["as"].to_s }
        bound << step["capture_final_path"].to_s if step["capture_final_path"]
      end
    end
  end

  def test_every_pattern_compiles_and_every_assertion_names_a_capture
    FLOWS.each do |flow|
      counts = []
      flow["steps"].each do |step|
        label = "#{flow["id"]}/#{step["name"]}"
        patterns = Array(step["expect_body"]) + Array(step["expect_any"]) + Array(step["forbid_body"]) +
                   Array(step["capture"]).map { |c| c["pattern"] } + Array(step["number"]).map { |c| c["pattern"] } +
                   Array(step["mail"] && step["mail"]["capture"]).map { |c| c["pattern"] }
        patterns << step["count"]["pattern"] if step["count"]
        want = step["expect_final_path"]
        patterns += want.slice("matches", "not_matches").values if want.is_a?(Hash)
        patterns.each do |pattern|
          Regexp.new(pattern.gsub(/\$[A-Za-z_]\w*/, "x"))
        rescue RegexpError => e
          flunk "#{label}: #{pattern.inspect} does not compile (#{e.message})"
        end
        counts << step["count"]["as"].to_s if step["count"]
        counts += Array(step["number"]).map { |c| c["as"].to_s }
      end
      Array(flow["assert"]).each do |rule|
        assert_includes counts, rule["left"].to_s, "#{flow["id"]}: assert left #{rule["left"]} is not a count/number capture"
        right = rule["right"]
        assert_includes counts, right.to_s, "#{flow["id"]}: assert right #{right} is not a capture" unless right.is_a?(Integer)
      end
    end
  end

  # vps-deploy runs flow_journey against the apps it has just restarted, and the
  # port it probes serves production. A journey that signs up, posts or orders
  # without being told to stay off that host would write test rows into the live
  # database on every deploy.
  NO_WRITE_NEEDED = %w[master_unlock_refuses_a_wrong_token].freeze

  def test_every_journey_that_writes_without_credentials_is_marked_mutates
    FLOWS.select { |flow| writes?(flow) && !flow["requires_credentials"] && !NO_WRITE_NEEDED.include?(flow["id"]) }.each do |flow|
      assert flow["mutates"], "#{flow["id"]} posts but is not marked mutates: true, so it would run against production"
    end
  end

  def test_writes_are_refused_on_the_deploy_host_unless_told_otherwise
    coverage = Deploy::FlowCoverage

    refute coverage.writes_allowed?({}, vps: true)
    assert coverage.writes_allowed?({}, vps: false)
    assert coverage.writes_allowed?({ "CHECK_ALLOW_WRITES" => "1" }, vps: true)
    refute coverage.writes_allowed?({ "CHECK_NO_WRITES" => "1" }, vps: false)
  end

  def test_the_check_sends_no_request_for_a_mutating_flow_on_the_deploy_host
    Dir.mktmpdir do |dir|
      path = File.join(dir, "flows.yml")
      File.write(path, { "flows" => [{ "id" => "writes", "app" => "brgen", "mutates" => true,
                                      "steps" => [{ "name" => "post", "post" => "/posts" }] }] }.to_yaml)
      klass = Deploy::FlowJourneyCheck::FlowClient
      klass.singleton_class.send(:alias_method, :real_new, :new)
      klass.define_singleton_method(:new) { |**| raise "a request was about to be made against production" }
      original = CrawlSupport.method(:port_open?)
      CrawlSupport.define_singleton_method(:port_open?) { |*| true }
      begin
        result = with_env("DEPLOY_ASSUME_VPS" => "1", "CHECK_ALLOW_WRITES" => nil, "CHECK_NO_WRITES" => nil) { Deploy::FlowJourneyCheck.new(path:).run }
      ensure
        CrawlSupport.define_singleton_method(:port_open?, original)
        klass.singleton_class.send(:alias_method, :new, :real_new)
        klass.singleton_class.send(:remove_method, :real_new)
      end

      assert_empty result.failures
      assert_includes result.unchecked.first, "serves production"
    end
  end

  # --- coverage ---------------------------------------------------------------

  def test_every_declared_app_has_a_flow_that_writes
    APPS.each do |app|
      writers = FLOWS.select { |flow| flow["app"] == app && writes?(flow) }
      refute_empty writers, "#{app} has no journey that changes state; its flows only prove a stranger sees no 500"
    end
  end

  # brgen is one app and eight hosts. A guest can write on every vertical host
  # below; maps is the one read-only exception (a check-in needs a place, and a
  # fresh database has none), listed so that a new maps write flow has to delete
  # the exception rather than leave it standing.
  VERTICAL_WRITES = {
    "brgen.no" => "core: posts, votes, comments, messenger, sign-up, sign-in",
    "markedsplass.brgen.no" => "marketplace: list an item, cart",
    "takeaway.brgen.no" => "takeaway: order",
    "dating.brgen.no" => "dating: like",
    "radio.brgen.no" => "playlist: create",
    "tv.brgen.no" => "tv: subscribe",
  }.freeze
  READ_ONLY_VERTICALS = %w[maps.brgen.no].freeze

  def flow_hosts(flow)
    ([flow["host"]] + flow["steps"].select { |s| s.key?("post") }.map { |s| s["host"] }).compact.uniq
  end

  def test_every_brgen_vertical_a_guest_can_write_to_has_a_writing_journey
    brgen = FLOWS.select { |flow| flow["app"] == "brgen" && writes?(flow) }
    written = brgen.flat_map { |flow| flow_hosts(flow).empty? ? ["brgen.no"] : flow_hosts(flow) }.uniq
    VERTICAL_WRITES.each_key { |host| assert_includes written, host, "no writing journey on #{host} (#{VERTICAL_WRITES[host]})" }
    READ_ONLY_VERTICALS.each { |host| refute_includes written, host, "#{host} now has a writing journey; remove it from READ_ONLY_VERTICALS" }
  end

  def test_the_flow_types_the_operator_named_each_have_a_journey
    posts = ->(flow, fragment) { flow["steps"].any? { |s| s["post"].to_s.include?(fragment) } }
    {
      "sign-up" => ->(f) { posts.(f, "/users") || posts.(f, "/registration") },
      "sign-in/out" => ->(f) { posts.(f, "/session") },
      "password reset" => ->(f) { posts.(f, "/passwords") },
      "email confirmation" => ->(f) { f["steps"].any? { |s| s.key?("mail") } },
      "post create" => ->(f) { posts.(f, "/posts") },
      "comment/reply" => ->(f) { posts.(f, "/comments") },
      "vote" => ->(f) { posts.(f, "/vote") },
      "report" => ->(f) { posts.(f, "/reports") },
      "messenger send" => ->(f) { posts.(f, "/messages") },
      "marketplace listing" => ->(f) { posts.(f, "/listings") },
      "cart" => ->(f) { f["steps"].any? { |s| s["get"].to_s == "/cart" } && posts.(f, "/orders") },
      "takeaway order" => ->(f) { posts.(f, "/restaurants/") },
      "dating swipe" => ->(f) { posts.(f, "/likes") },
      "playlist" => ->(f) { posts.(f, "/playlists") },
      "search then open" => ->(f) { f["steps"].any? { |s| s["get"].to_s.start_with?("/search?q=$") } },
      "locale" => ->(f) { f["id"].include?("locale") && f["steps"].map { |s| s["host"] }.compact.uniq.size > 1 },
      "pwa" => ->(f) { f["steps"].any? { |s| s["get"].to_s.include?("service-worker") } },
    }.each do |type, matcher|
      assert FLOWS.any? { |flow| matcher.(flow) }, "no journey covers: #{type}"
    end
  end

  def test_the_vote_journey_asserts_that_a_repeat_withdraws_and_a_flip_replaces
    flow = FLOWS.find { |f| f["id"] == "brgen_vote_up_down_toggles" }
    rules = flow.fetch("assert")

    assert(rules.any? { |r| r["delta"] == 1 }, "an upvote must be asserted to add one")
    assert(rules.count { |r| r["delta"] == -1 } >= 2, "a downvote and a flip must be asserted to subtract one")
    assert(rules.count { |r| r["right"] == "s0" && !r.key?("delta") } >= 2, "voting the same way twice must be asserted to withdraw")
  end

  # --- the skip -----------------------------------------------------------------

  def with_ports_closed
    original = CrawlSupport.method(:port_open?)
    CrawlSupport.define_singleton_method(:port_open?) { |*| false }
    yield
  ensure
    CrawlSupport.define_singleton_method(:port_open?, original)
  end

  def with_env(pairs)
    saved = pairs.keys.to_h { |key| [key, ENV[key]] }
    pairs.each { |key, value| ENV[key] = value }
    yield
  ensure
    saved.each { |key, value| ENV[key] = value }
  end

  def test_a_check_whose_apps_are_all_down_names_each_app_and_is_not_green
    result = with_ports_closed do
      with_env("CHECK_REQUIRE_LIVE" => nil, "CHECK_SOURCE_ONLY" => nil, "FLOW_BRGEN_PORT" => nil, "FLOW_AMBER_PORT" => nil,
               "FLOW_BSDPORTS_PORT" => nil, "FLOW_MASTER_PORT" => nil) { Deploy::FlowJourneyCheck.new.run }
    end

    assert_equal :inconclusive, result.outcome
    refute result.conclusive?
    assert_equal APPS.sort, Deploy::FlowCoverage.down_apps(result).sort, "every declared app is named as skipped:app-down"
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

  def check_with_result
    check = Deploy::FlowJourneyCheck.new
    check.instance_variable_set(:@result, Deploy::CheckResult.new)
    check
  end

  def check_failures(check) = check.instance_variable_get(:@result).failures

  def response(body, path: "/", code: 200)
    Deploy::FlowJourneyCheck::FlowClient::Response.new(code:, body:, final_url: "http://brgen.no#{path}", redirects: [])
  end

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

  def strings_in(value)
    case value
    when String then [value]
    when Hash then value.flat_map { |k, v| strings_in(k) + strings_in(v) }
    when Array then value.flat_map { |v| strings_in(v) }
    else []
    end
  end
end
