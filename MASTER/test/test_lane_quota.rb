# frozen_string_literal: true

require "test_helper"
require "open3"
require "tmpdir"
require "open3"
require "rbconfig"

# A provider that answers "Individual quota reached ... Resets in 165h22m49s"
# must not be asked again by any selection path: one spent reply kills the lane
# until the stated reset, across processes, and every path reads one function.
class TestLaneQuota < Minitest::Test
  Quota = Master::Io::LaneQuota
  Silence = Master::Io::LaneSilence
  Health = Master::Io::LaneHealth
  AGY_REPLY = "agy: error: Individual quota reached. Please upgrade your subscription to increase your limits. Resets in 165h22m49s."

  def setup
    @dir = Dir.mktmpdir
    @now = Time.now.to_f
    Quota.path = File.join(@dir, "lane_quota.yml")
    Quota.clock = -> { @now }
  end

  # A door test parks the model it failed; selection reads that park, so it
  # must not reach the next test (seed 63433 ordered one ahead of agy's).
  def teardown
    Master::Io::ModelSkipCache.clear!
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

  def test_selection_skips_a_quota_dead_lane_without_a_hand_entry
    models = %w[agy:auto claude-cli:claude-sonnet-5-5]
    assert_equal "claude-cli:claude-sonnet-5-5", Master::Io::LaneSelection.first_live(models), "claude-cli leads agy"
    assert_equal "agy:auto", Master::Io::LaneSelection.first_live(%w[agy:auto deepseek-chat])

    Quota.note("agy:auto", AGY_REPLY)
    assert_equal "claude-cli:claude-sonnet-5-5", Master::Io::LaneSelection.first_live(models)
  end

  def test_the_real_data_file_names_dead_lanes_as_strings
    assert_includes Quota.manual_dead, "gemini"
    assert(Quota.manual_dead.none? { |e| e.include?("=>") })
  end

  def test_recovery_canary_resolves_manually_disabled_lanes_across_all_tiers
    gemini = Health.model_for_lane("gemini")
    codex = Health.model_for_lane("codex-cli")

    assert_match(/\Agemini(?:-|:)/, gemini.to_s)
    assert_equal "codex-cli:auto", codex
  end

  def test_manual_lane_exclusions_are_reprobed_and_recovered_from_evidence
    assert Quota.dead?("gemini-2.5-flash")

    assert_equal ["gemini"], Quota.due_manual_probes(known: ["gemini"], every: 600)
    assert_empty Quota.due_manual_probes(known: ["gemini"], every: 600)
    @now += 601
    assert_equal ["gemini"], Quota.due_manual_probes(known: ["gemini"], every: 600)

    Silence.silence("gemini", reason: "previous failed probe")
    assert Silence.refuses?("gemini-2.5-flash")

    Quota.with_manual_probe("gemini") do
      refute Quota.dead?("gemini-2.5-flash"), "the canary alone can bypass the manual exclusion"
      refute Silence.refuses?("gemini-2.5-flash"), "the canary must reach the provider past old silence"
    end
    assert Quota.dead?("gemini-2.5-flash"), "outside the canary, it remains excluded until proof"
    assert Silence.refuses?("gemini-2.5-flash"), "the ordinary silence remains in place"
    Silence.record(true, "gemini")
    Quota.revive_manual("gemini")
    refute Quota.dead?("gemini-2.5-flash"), "a verified answer retires the stale exclusion"
    refute_includes Quota.manual_dead, "gemini"
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

  def test_openrouter_free_pool_quota_is_shared_across_vendor_prefixed_models
    reply = "rate_limit: Rate limit exceeded: free-models-per-day-high-balance."
    Quota.note("nvidia/nemotron-3-super-120b-a12b:free", reply)

    assert_equal "nvidia", Quota.lane_of("nvidia/nemotron-3-super-120b-a12b:free")
    assert_equal "google", Quota.lane_of("google/gemma-4-31b-it:free")
    assert_equal "nvidia", Silence.lane_of("nvidia/nemotron-3-super-120b-a12b:free")
    assert Quota.dead?("google/gemma-4-31b-it:free")
    assert Quota.dead?("nvidia/nemotron-3.5-lightning:free")
    refute Quota.dead?("nvidia/nemotron-paid")

    Quota.revive("openrouter-free")
    Quota.note("nvidia/nemotron-3-super-120b-a12b:free", "HTTP 429 Retry-After: 900")
    assert Quota.dead?("nvidia/another:free"), "same vendor's short 429 is vendor-scoped"
    refute Quota.dead?("google/gemma-4-31b-it:free"), "a vendor 429 is not the shared free-pool limit"

    Quota.revive("nvidia")
    Quota.note(
      "nvidia/nemotron-3-super-120b-a12b:free",
      "HTTP 429 X-RateLimit-Reset: 1791800000000",
    )
    assert Quota.dead?("nvidia/another:free")
    refute Quota.dead?("google/gemma-4-31b-it:free"),
           "a reset timestamp without an explicit free-pool refusal stays vendor-scoped"
  end

  def test_lane_normalization_preserves_hyphenated_cli_provider_names
    assert_equal "claude-cli", Quota.lane_of("claude-cli:claude-opus-5-5")
    assert_equal "grok-cli", Quota.lane_of("grok-cli:auto")
    assert_equal "deepseek", Quota.lane_of("deepseek-chat")
    assert_equal "google", Quota.lane_of("google/gemini-2.5-flash")
  end

  def test_browser_chat_failures_are_scoped_to_the_website
    Silence.record(true, "web-chat:grok")
    Silence.record(true, "web-chat:chatgpt")
    assert_equal "web-chat:grok", Quota.lane_of("web-chat:grok")
    assert_equal "web-chat:chatgpt", Quota.lane_of("web-chat:chatgpt")
    refute_equal Quota.lane_of("web-chat:grok"), Quota.lane_of("web-chat:chatgpt")
    assert_equal "web-chat:grok", Silence.lane_of("web-chat:grok")
    Silence::SILENT_AFTER.times { Silence.record(false, "web-chat:grok", reason: "website failure") }
    assert Silence.silent?("web-chat:grok")
    refute Silence.silent?("web-chat:chatgpt"), "Grok's failures must not silence ChatGPT"
  ensure
    Silence.record(true, "web-chat:grok")
    Silence.record(true, "web-chat:chatgpt")
  end

  def test_status_reports_global_free_pool_quota_instead_of_misleading_vendor_silence
    reply = "rate_limit: Rate limit exceeded: free-models-per-day-high-balance."
    Quota.note("nvidia/nemotron-3-super-120b-a12b:free", reply)

    assert_match(/\Aopenrouter-free: quota spent/, Quota.report_for("google/gemma-4-31b-it:free"))
    assert_equal [
      Quota.report_for("google/gemma-4-31b-it:free"),
    ], Health.states(
      ["nvidia/nemotron-3-super-120b-a12b:free", "google/gemma-4-31b-it:free"],
      refuses: ->(model) { Quota.dead?(model) },
    )
  end
end
