# frozen_string_literal: true

require "test_helper"
require "tmpdir"

# 2026-10-11: agy answered "Individual quota reached ... Resets in 165h22m49s"
# and every selection path went on asking it. One spent reply now kills the lane
# until the stated reset, across processes, and every path reads one function.
class TestLaneQuota < Minitest::Test
  Quota = Master::Io::LaneQuota
  Silence = Master::Review::LLMDispatcher::LaneSilence
  AGY_REPLY = "agy: error: Individual quota reached. Please upgrade your subscription to increase your limits. Resets in 165h22m49s."

  def setup
    @dir = Dir.mktmpdir
    @now = Time.now.to_f
    Quota.path = File.join(@dir, "lane_quota.yml")
    Quota.clock = -> { @now }
  end

  def teardown
    Quota.path = nil
    Quota.clock = -> { Time.now.to_f }
    FileUtils.remove_entry(@dir)
  end

  def test_reset_durations_in_the_forms_providers_use
    assert_equal 165 * 3600 + 22 * 60 + 49, Quota.wait_in(AGY_REPLY)
    assert_equal 7200, Quota.wait_in("quota exceeded, resets in 2h")
    assert_equal 900, Quota.wait_in("rate limited: try again in 15 minutes")
    assert_equal 30, Quota.wait_in("HTTP 429 Retry-After: 30")
    assert_nil Quota.wait_in("quota reached")
  end

  def test_ordinary_failures_are_not_quota
    refute Quota.spent?("agy: timed out after 120s")
    refute Quota.spent?("line 429 of the report is wrong")
    assert Quota.spent?("HTTP 429 too many requests"), "a bare 429 is a limit with no stated time"
    assert Quota.spent?("HTTP 429 Retry-After: 30")
  end

  def test_one_spent_reply_kills_the_lane_and_leaves_the_others
    assert_equal @now + 595_369, Quota.note("agy:auto", AGY_REPLY)

    assert Quota.dead?("agy:auto")
    assert Quota.dead?("agy:other"), "the lane is dead, not the model"
    refute Quota.dead?("claude-cli:claude-opus-5-5")
    assert Silence.refuses?("agy:auto")
    refute Silence.refuses?("claude-cli:claude-opus-5-5")
    assert_match(/\Aagy: quota spent, back in 165h/, Silence.refusal("agy:auto"))
  end

  def test_unknown_wait_is_an_hour_and_a_long_wait_is_capped
    Quota.note("a:x", "quota reached")
    Quota.note("b:x", "quota reached, resets in 9000h")

    assert_equal @now + 3600, Quota.until_for("a:x")
    assert_equal @now + 8 * 86_400, Quota.until_for("b:x")
  end

  def test_state_survives_a_fresh_process
    Quota.note("agy:auto", AGY_REPLY)
    ruby = <<~RUBY
      require "./lib/master"
      Master::Io::LaneQuota.path = ARGV[0]
      print Master::Io::LaneQuota.dead?("agy:auto")
    RUBY
    out, = Open3.capture2e(RbConfig.ruby, "-e", ruby, Quota.path, chdir: File.expand_path("..", __dir__))
    assert_equal "true", out.lines.last.to_s.strip
  end

  def test_report_names_why_each_lane_died_and_the_file_keeps_it
    Quota.note("agy:auto", AGY_REPLY)
    Quota.note("lmstudio:qwen", "ollama unreachable at http://localhost:11434: Connection refused")
    Quota.note("claude-cli:x", "Please run /login")
    Quota.note("deepseek:chat", "HTTP 429")

    rows = Quota.report.to_h { |row| row.split(": ", 2) }
    assert_match(/\Aquota spent, back in 165h/, rows.fetch("agy"))
    assert_match(/\Aunreachable, back in/, rows.fetch("lmstudio"))
    assert_match(/\Alogin expired, back in/, rows.fetch("claude-cli"))
    assert_match(/\Aquota spent, wait guessed, back in/, rows.fetch("deepseek"))
    assert_equal "unreachable", YAML.safe_load_file(Quota.path).fetch("reason:lmstudio")

    Quota.revive("lmstudio")
    refute YAML.safe_load_file(Quota.path).key?("reason:lmstudio")
    refute(Quota.report.any? { |row| row.start_with?("lmstudio:") })
  end

  def test_expiry_revives_the_lane
    Quota.note("agy:auto", "quota reached, resets in 1h")
    @now += 3599
    assert Quota.dead?("agy:auto")
    @now += 2
    refute Quota.dead?("agy:auto")
    refute(Quota.report.any? { |row| row.start_with?("agy:") })
  end

  def test_manual_list_and_persisted_deaths_share_one_reader
    manual = Quota.manual_dead({ "dead" => ["codex-cli:", { "grok-cli" => nil }, "ollama:glm"] })
    assert_equal %w[codex-cli grok-cli ollama:glm], manual

    assert Quota.dead?("grok-cli:auto", manual:)
    Quota.note("agy:auto", AGY_REPLY)
    assert Quota.dead?("agy:auto", manual:)
    refute Quota.dead?("claude-cli:x", manual:)
    assert_equal :manual, Quota.until_for("ollama:glm-4", manual:)
  end

  def test_roles_skip_a_quota_dead_lane_without_a_hand_entry
    cfg = { "roles" => { "critic" => %w[agy:auto claude-cli:claude-sonnet-5-5], "fixer" => %w[claude-cli:claude-opus-5-5] } }
    assert_equal "agy:auto", Master::Fix::ModelRoles.assign(env: {}, alive: ->(_) { true }, cfg:).critic

    Quota.note("agy:auto", AGY_REPLY)
    assert_equal "claude-cli:claude-sonnet-5-5", Master::Fix::ModelRoles.assign(env: {}, alive: ->(_) { true }, cfg:).critic
  end

  def test_the_real_data_file_names_dead_lanes_as_strings
    assert_includes Quota.manual_dead, "gemini"
    assert(Quota.manual_dead.none? { |e| e.include?("=>") })
  end

  # The dispatcher learns from one settled reply, then neither the door, the
  # council's pinned critic, nor failover reaches agy; claude still answers.
  def test_dispatcher_door_pin_and_failover_honour_it
    dispatcher = Master::Review::LLMDispatcher.allocate
    dispatcher.instance_variable_set(:@bus, nil)
    calls = []
    dispatcher.define_singleton_method(:send_llm_request) { |model, *_a, **_k| calls << model; Master::Result.ok("hi") }

    err = Master::Result.err(AGY_REPLY, category: :provider_error)
    dispatcher.send(:settle, err, "agy:auto", 0.0)

    refused = dispatcher.send_with_cache("agy:auto", [{ role: "user", content: "hi" }])
    assert_equal :no_api_key, refused.category
    assert_match(/agy: quota spent/, refused.message)
    assert_empty calls, "a dead lane must not be called"

    pinned = Master::Review::LLMDispatcher::ModelPin.with("agy:auto") do
      dispatcher.send(:answering_model, "claude-cli:claude-opus-5-5", nil)
    end
    assert_equal "claude-cli:claude-opus-5-5", pinned, "a pinned dead lane yields to the live one"
    refute Silence.refuses?(pinned)
  end

  def test_agent_failover_skips_a_dead_lane
    Quota.note("agy:auto", AGY_REPLY)
    agent = Master::Review::Agent.allocate
    hops = []
    agent.instance_variable_set(:@dispatcher, Object.new.tap do |d|
      d.define_singleton_method(:send_with_cache) { |model, *_a, **_k| hops << model; Master::Result.ok("ok") }
    end)
    agent.instance_variable_set(:@bus, nil)
    agent.define_singleton_method(:single_call_fallback_models) { %w[agy:auto claude-cli:claude-sonnet-5-5] }
    agent.define_singleton_method(:record_single_call_substitution) { |_f, _t, result, **| result }

    agent.send(:retry_on_broke_lane, Master::Result.err("boom", category: :provider_error), "x:y", [{ role: "user", content: "hi" }])

    assert_equal %w[claude-cli:claude-sonnet-5-5], hops
  end
end
