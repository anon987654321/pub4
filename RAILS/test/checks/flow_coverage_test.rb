# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require "yaml"
require_relative "../../../MASTER/checks/lib/live/flow_journey"
require_relative "../../../MASTER/checks/lib/live/user_flow"
require_relative "support/flow_coverage_sources"

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
  include FlowCoverageSources

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
    FLEET.each do |app|
      writers = FLOWS.select { |flow| flow["app"] == app && writes?(flow) }
      refute_empty writers, "#{app} has no journey that changes state; its flows only prove a stranger sees no 500"
    end
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
end
