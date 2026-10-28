# frozen_string_literal: true

require_relative "../test_helper"

class TestVoiceNarrator < Minitest::Test
  Narrator = Master::Voice::Narrator

  CONFIG = Narrator.load_config.merge("poll_s" => 0.01).freeze

  class Clock
    attr_accessor :now

    def initialize = (@now = 100.0)
    def call = @now
    def advance(seconds) = (@now += seconds)
  end

  def build(writer: nil, config: {}, backlog: 0, env: {})
    @clock = Clock.new
    @spoken = []
    @backlog = backlog
    Narrator.new(
      config: CONFIG.merge(config),
      writer: writer || ->(**) { raise Narrator::LaneWriter::Unavailable, "no lane" },
      speaker: ->(sentence) { @spoken << sentence },
      backlog: -> { @backlog },
      audible: -> { true },
      clock: @clock,
      env:,
    )
  end

  def window(narrator) = @clock.advance(narrator.instance_variable_get(:@config).fetch("batch_window_s") + 0.1)

  def test_shipped_config_is_on_and_complete
    assert_equal true, CONFIG["enabled"]
    %w[lane_tier max_tokens batch_window_s max_gap_s max_sentences_per_minute max_cost_usd est_cost_per_call_usd
       hold_after_interrupt_s max_backlog].each { |key| assert CONFIG.key?(key), key }
  end

  def test_template_story_has_beginning_middle_and_end
    n = build
    n.observe("scan0: reading 14 files")
    window(n)
    assert_equal :spoken, n.tick
    n.observe("scan0: found 3 findings")
    window(n)
    assert_equal :spoken, n.tick
    n.observe("fix0: complete, 2 repairs")
    assert_equal :spoken, n.tick
    assert_equal 3, @spoken.size
    assert_match(/begins|starts/i, @spoken.first)
    assert_match(/reading 14 files/, @spoken.first)
    assert_match(/complete|done|end/i, @spoken.last)
    assert_equal 0, n.beats
  end

  def test_incomplete_is_never_narrated_as_success
    n = build
    n.observe("fix0: incomplete, semantic assessment unavailable")
    assert_equal :spoken, n.tick
    assert_match(/stopped|did not finish/i, @spoken.join)
    refute_match(/task is done|task is complete|work is complete/i, @spoken.join)
    assert_equal 0, n.beats
  end

  def test_routine_scan_counters_and_heartbeats_are_ignored
    n = build
    refute n.observe("obs0: 46/2708 files, 286 violations in 24 files, 5s, eta 293s")
    refute n.observe("law0: lexical scan pass=lexical law=NO_DEBUG file=task.rb checks=123")
    refute n.observe("+ route 400s")
  end

  def test_narration_uses_strunk_without_deleting_meaning
    n = build(writer: ->(**) { "Certainly, the repair could not be verified." })
    n.observe("review0: repair could not be verified")
    window(n)
    assert_equal :spoken, n.tick
    assert_equal "the repair could not be verified.", @spoken.first
  end

  def test_nothing_is_told_before_the_batch_window
    n = build
    n.observe("scan0: reading")
    assert_equal :wait, n.tick
    assert_empty @spoken
  end

  def test_dead_air_gets_a_still_at_it_line_twice_then_silence
    n = build
    n.observe("check1: running suites")
    window(n)
    n.tick
    @clock.advance(15)
    assert_equal :spoken, n.tick
    @clock.advance(15)
    assert_equal :spoken, n.tick
    @clock.advance(15)
    assert_equal :wait, n.tick
    assert_match(/running suites/, @spoken.last)
  end

  def test_idle_task_closes_silently
    n = build
    n.observe("check1: running suites")
    window(n)
    n.tick
    @clock.advance(200)
    assert_equal :wait, n.tick
    assert_equal 0, n.beats
  end

  def test_model_text_is_used_and_checked
    seen = []
    writer = lambda do |system:, prompt:, max_tokens:|
      seen << [system, prompt, max_tokens]
      "The scan has read 14 files. Three findings are waiting."
    end
    n = build(writer:)
    n.observe("scan0: reading 14 files, 3 findings are waiting")
    window(n)
    assert_equal :spoken, n.tick
    assert_equal ["The scan has read 14 files.", "Three findings are waiting."], @spoken
    assert_equal CONFIG["max_tokens"], seen.first[2]
    assert_match(/1\. scan0: reading 14 files/, seen.first[1])
    assert_equal 1, n.calls
  end

  def test_invented_numbers_fall_back_to_the_template
    n = build(writer: ->(**) { "The scan read 900 files." })
    n.observe("scan0: reading 14 files")
    window(n)
    n.tick
    refute_match(/900/, @spoken.join)
    assert_match(/14 files/, @spoken.join)
  end

  def test_unrelated_story_falls_back_to_the_observed_event
    n = build(writer: ->(**) { "The moon is a really committed pebble." })
    n.observe("scan0: reading 14 files")
    window(n)

    assert_equal :spoken, n.tick
    refute_match(/moon|committed|pebble/i, @spoken.join)
    assert_match(/14 files/, @spoken.join)
  end

  def test_model_cannot_claim_success_for_an_incomplete_run
    n = build(writer: ->(**) { "The task is complete." })
    n.observe("fix0: incomplete, semantic assessment unavailable")

    assert_equal :spoken, n.tick
    refute_match(/\b(?:complete|done|finished|successful|verified)\b/i, @spoken.join)
    assert_match(/stopped|did not finish/i, @spoken.join)
  end

  def test_refusals_and_repeats_are_not_spoken
    n = build(writer: ->(**) { "I'm sorry, I cannot do that." })
    n.observe("scan0: reading")
    window(n)
    n.tick
    refute_match(/sorry/i, @spoken.join)

    m = build(writer: ->(**) { "The suite is running." })
    m.observe("check1: running")
    window(m)
    m.tick
    m.observe("check1: still running")
    window(m)
    m.tick
    assert_equal 2, @spoken.size
    refute_equal @spoken.first, @spoken.last
  end

  def test_secrets_paths_and_urls_are_never_spoken_or_prompted
    prompts = []
    n = build(writer: ->(prompt:, **) { prompts << prompt; "The key was found in the file." })
    n.observe("env0: OPENAI_API_KEY=sk-abcdefghijklmnopqrstuvwxyz0123456789 loaded from /etc/master.env")
    n.observe("net0: fetched https://example.com/a?token=abc123 at /Users/mac/Documents/GitHub/pub4/MASTER/lib/x.rb commit 9b7cfebb1")
    window(n)
    n.tick
    blob = prompts.join + @spoken.join
    refute_match(/sk-|abcdefghijkl|OPENAI|example\.com|token=|\/Users|\/etc|9b7cfebb1/, blob)
    assert_match(/x\.rb/, prompts.join)
  end

  def test_sentence_cap_per_minute
    n = build(config: { "max_sentences_per_minute" => 2 })
    3.times do |i|
      n.observe("step#{i}: working on part #{i}")
      window(n)
      n.tick
    end
    assert_equal 2, @spoken.size
    assert_equal :rate, n.tick.then { n.observe("step9: more"); window(n); n.tick }
    @clock.advance(61)
    n.observe("step10: later")
    window(n)
    assert_equal :spoken, n.tick
  end

  def test_cost_cap_ends_model_use
    calls = 0
    n = build(writer: ->(**) { calls += 1; "Work number #{calls} moves along." }, config: { "max_cost_usd" => 0.002, "est_cost_per_call_usd" => 0.001, "max_sentences_per_minute" => 99 })
    5.times do |i|
      n.observe("step#{i}: part #{i}")
      window(n)
      n.tick
    end
    assert_equal 2, calls
    assert_equal 5, @spoken.size
    assert_in_delta 0.002, n.cost_usd
  end

  def test_failing_lane_backs_off
    calls = 0
    n = build(writer: ->(**) { calls += 1; raise "dead" }, config: { "max_sentences_per_minute" => 99 })
    6.times do |i|
      n.observe("step#{i}: part #{i}")
      window(n)
      n.tick
    end
    assert_equal 2, calls
    assert_equal 6, @spoken.size
  end

  def test_compose_waits_while_the_speaker_is_busy
    n = build(backlog: 2)
    n.observe("scan0: reading")
    window(n)
    assert_equal :backlog, n.tick
    @backlog = 1
    assert_equal :spoken, n.tick
  end

  def test_interrupt_drops_pending_and_holds
    n = build
    n.observe("scan0: reading")
    window(n)
    n.interrupt
    assert_equal :held, n.tick
    n.observe("scan0: more")
    @clock.advance(CONFIG["hold_after_interrupt_s"] + 0.1)
    window(n)
    assert_equal :spoken, n.tick
    assert_equal 1, @spoken.size
    assert_match(/more/, @spoken.first)
  end

  def test_a_beat_in_flight_is_dropped_when_halted
    n = build
    writer = lambda do |**|
      n.halt!
      "A sentence nobody should hear."
    end
    n.instance_variable_set(:@writer, writer)
    n.observe("scan0: reading")
    window(n)
    assert_equal :halted, n.tick
    assert_empty @spoken
  end

  def test_off_switches
    assert_equal false, build(env: { "MASTER_NARRATE" => "0" }).enabled?
    assert_equal false, build(config: { "enabled" => false }).enabled?
    n = build(env: { "MASTER_NARRATE" => "0" })
    n.enable!
    assert n.enabled?
    n.observe("scan0: reading")
    n.disable!
    refute n.observe("scan0: reading")
    assert_equal :off, n.tick
  end

  def test_ignored_lines_are_not_events
    n = build
    refute n.observe("voice0 at mainbus0: on")
    refute n.observe("llm1: tokens 4000")
    refute n.observe("   ")
  end

  def test_findings_beat_is_told_as_a_finding
    n = build
    n.observe("scan0: reading")
    window(n)
    n.tick
    n.observe("check2: failed, timeout in suite")
    window(n)
    n.tick
    assert_match(/turned up|problem/i, @spoken.last)
  end

  def test_lane_writer_uses_the_tier_and_skips_unsupported_lanes
    lanes = Object.new
    def lanes.tier(name) = ["grok-cli:auto", "claude-cli:sonnet"].tap { @asked = name }
    def lanes.order(ids) = ids
    def lanes.alive?(_id) = true
    runner = Object.new
    def runner.capture3(*cmd, **opts) = ["Said plainly.", "", Struct.new(:ok) { def success? = ok }.new(true)].tap { @cmd = cmd }
    writer = Narrator::LaneWriter.new({ "lane_tier" => "fast", "model_timeout_s" => 5 }, lanes:, runner:)
    assert_equal "claude-cli:sonnet", writer.pick
    assert_equal "Said plainly.", writer.call(system: "s", prompt: "p", max_tokens: 90)
    assert_equal "fast", lanes.instance_variable_get(:@asked)
  end

  def test_lane_writer_raises_when_no_lane_is_live
    lanes = Object.new
    def lanes.tier(_name) = ["claude-cli:sonnet"]
    def lanes.order(_ids) = []
    writer = Narrator::LaneWriter.new({ "lane_tier" => "fast" }, lanes:)
    assert_raises(Narrator::LaneWriter::Unavailable) { writer.call(system: "s", prompt: "p", max_tokens: 9) }
  end

  def test_facade_is_quiet_without_a_speaker
    Narrator.reset_instance!
    previous = ENV["MASTER_CLI_SPEAK"]
    ENV["MASTER_CLI_SPEAK"] = "0"
    refute Narrator.observe("scan0: reading")
  ensure
    previous.nil? ? ENV.delete("MASTER_CLI_SPEAK") : ENV["MASTER_CLI_SPEAK"] = previous
    Narrator.reset_instance!
  end

  def test_dmesg_feeds_the_story_and_does_not_read_the_line_twice
    fed = []
    spoke = []
    Master::Voice::Narrator.stub(:observe, ->(text) { fed << text }) do
      Master::Voice::Narrator.stub(:narrating?, true) do
        Master::Voice::Playback.stub(:enqueue, ->(text, **) { spoke << text }) do
          Master::Trace::Dmesg.with_log_voice { Master::Trace::Dmesg.emit("scan0: reading 14 files", io: StringIO.new, force: true) }
        end
      end
    end
    assert_equal ["scan0: reading 14 files"], fed
    assert_empty spoke
  end

  def test_narrate_command_and_help
    out = Master::CLI::CommandRegistry.dispatch_narrate(ctx: { args: "status" })
    assert_match(/\Anarr0 at voice0: (on|off)/, out)
    assert_match(/narrate on\|off/, Master::CLI::CommandRegistry::HELP_TOPICS.fetch("narrate")[:detail].join)
    assert_includes Master::CLI::CommandRegistry.build_names_for_test, "narrate" if Master::CLI::CommandRegistry.respond_to?(:build_names_for_test)
  end
end
