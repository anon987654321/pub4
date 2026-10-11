# frozen_string_literal: true

require "test_helper"
require "minitest/mock"
require "tmpdir"

# The always-online guarantee. Every remote lane is exhausted in turn with the
# reply that provider really sends, the next lane in the role list answers, and
# a counting stub proves no call goes to a lane already dead. When the last lane
# (a local Ollama model) is dead too, the answer is a typed Offline, not a crash.
class TestLaneFailover < Minitest::Test
  Quota = Master::Io::LaneQuota
  Health = Master::Io::LaneHealth
  Silence = Master::Review::LLMDispatcher::LaneSilence
  Roles = Master::Fix::ModelRoles

  CLAUDE = "You've hit your session limit · resets 5pm (Europe/Oslo)"
  AGY = "agy: error: Individual quota reached. Please upgrade your subscription to increase your limits. Resets in 165h22m49s."
  GROK = "Error: rate limit exceeded, try again in 20 minutes"
  HTTP429 = "HTTP 429 Too Many Requests"
  REFUSED = "ollama unreachable at http://localhost:11434: Connection refused - connect(2) for \"localhost\" port 11434 (Errno::ECONNREFUSED)"
  # 2026-10-11 12:00 UTC is 14:00 in Oslo (CEST).
  NOON = Time.utc(2026, 10, 11, 12, 0, 0).to_f

  def setup
    @dir = Dir.mktmpdir
    @now = NOON
    Quota.path = File.join(@dir, "lane_quota.yml")
    Quota.clock = -> { @now }
    @lists = YAML.safe_load_file(Roles::DATA).fetch("roles")
  end

  def teardown
    Quota.path = nil
    Quota.clock = -> { Time.now.to_f }
    @lists.values.flatten.each { |model| Silence.record(true, Silence.lane_of(model)) }
    FileUtils.remove_entry(@dir)
  end

  def spelling(model)
    case Quota.lane_of(model)
    when "claude-cli" then CLAUDE
    when "agy" then AGY
    when "grok-cli" then GROK
    when "ollama" then REFUSED
    else HTTP429
    end
  end

  # A real dispatcher door with the provider call replaced by a counting stub:
  # `dead` lanes answer in their own spelling, the rest answer "ok from <model>".
  def dispatcher(calls, failing)
    door = Master::Review::LLMDispatcher.allocate
    door.instance_variable_set(:@bus, nil)
    door.instance_variable_set(:@model_router, nil)
    door.instance_variable_set(:@cache, Object.new.tap { |c| c.define_singleton_method(:fetch) { |_key, _model, &blk| blk.call } })
    door.instance_variable_set(:@circuit_breaker, Object.new.tap { |c| c.define_singleton_method(:call) { |_cost, &blk| blk.call } })
    door.instance_variable_set(:@availability, Struct.new(:dispatch_deadline_s).new(5))
    spell = method(:spelling)
    door.define_singleton_method(:send_llm_request) do |model, *_a, **_k|
      calls << model
      failing.include?(Quota.lane_of(model)) ? Master::Result.err(spell.call(model), category: :provider_error) : Master::Result.ok("ok from #{model}")
    end
    door
  end

  def agent_over(door, models)
    agent = Master::Review::Agent.allocate
    agent.instance_variable_set(:@dispatcher, door)
    agent.instance_variable_set(:@bus, nil)
    agent.define_singleton_method(:single_call_fallback_models) { models }
    agent.define_singleton_method(:record_single_call_substitution) { |_f, _t, result, **| result }
    agent
  end

  def ask(agent, door, models)
    first = door.send_with_cache(models.first, [{ role: "user", content: "hi" }])
    agent.send(:retry_on_broke_lane, first, models.first, [{ role: "user", content: "hi" }])
  end

  def test_each_role_list_survives_losing_its_lanes_one_at_a_time
    Master.stub(:llm_reachable?, true) do
      @lists.each do |role, models|
        Quota.path = File.join(@dir, "#{role}.yml")
        lanes = models.map { |m| Quota.lane_of(m) }.uniq
        calls = []
        failing = []
        died = {}
        lanes[0...-1].each_with_index do |lane, index|
          failing << lane
          door = dispatcher(calls, failing)
          result = ask(agent_over(door, models), door, models)
          expected = models.find { |m| !failing.include?(Quota.lane_of(m)) }
          assert_equal "ok from #{expected}", result.to_s, "#{role}: after #{lane} died, #{expected} answers"
          died[lane] = calls.size
          assert_equal index + 1, failing.size
        end
        dead_calls = calls.select { |m| failing.include?(Quota.lane_of(m)) }
        assert_equal failing.sort, dead_calls.map { |m| Quota.lane_of(m) }.uniq.sort
        failing.each do |lane|
          later = calls.drop(died.fetch(lane)).select { |m| Quota.lane_of(m) == lane }
          assert_empty later, "#{role}: #{lane} is never asked after it died"
        end
        assert_equal "ollama", Quota.lane_of(models.last), "#{role} ends in a local lane"
      end
    end
  end

  def test_with_the_local_lane_dead_too_the_answer_is_a_typed_offline
    Master.stub(:llm_reachable?, true) do
      models = @lists.fetch("fixer")
      calls = []
      lanes = models.map { |m| Quota.lane_of(m) }.uniq
      door = dispatcher(calls, lanes)
      agent = agent_over(door, models)

      result = ask(agent, door, models)
      assert_equal :offline, result.category
      assert_match(/\Aoffline: no lane answers; .*ollama: unreachable/, result.message)
      assert_match(/claude-cli: quota spent, back in 3h/, result.message)
      assert_raises(Health::Offline) { agent.send(:raise_failure, result) }

      before = calls.size
      again = ask(agent, door, models)
      assert_equal :offline, again.category
      assert_equal before, calls.size, "nothing is asked of a dead lane"
    end
  end

  def test_the_real_spellings_are_read
    assert_equal 3 * 3600, Quota.wait_in(CLAUDE)
    assert_equal 20 * 60, Quota.wait_in(GROK)
    assert_equal NOON + 3 * 3600, Quota.note("claude-cli:x", CLAUDE)
    assert_equal NOON + 60, Quota.note("ollama:x", REFUSED)
    assert_equal NOON + 3600, Quota.note("deepseek-chat", HTTP429)
    assert_equal NOON + 3600, Quota.note("grok-cli:auto", "401 Unauthorized, please run /login")
  end

  def test_clock_forms_zone_and_rollover
    zone = ENV.fetch("TZ", nil)
    assert_equal 3 * 3600, Quota.wait_in("resets 5pm (Europe/Oslo)")
    assert_equal 3 * 3600 + 1800, Quota.wait_in("resets 5:30pm (Europe/Oslo)")
    assert_equal 3 * 3600, Quota.wait_in("resets at 17:00 (Europe/Oslo)")
    @now = Time.utc(2026, 10, 11, 16, 30, 0).to_f
    assert_equal 22 * 3600 + 1800, Quota.wait_in("resets 5pm (Europe/Oslo)"), "already past: tomorrow"
    zone.nil? ? assert_nil(ENV.fetch("TZ", nil)) : assert_equal(zone, ENV.fetch("TZ", nil))
  end

  def test_a_bare_limit_is_probed_again_and_a_stated_one_is_not
    Quota.note("agy:auto", HTTP429)
    Quota.note("claude-cli:x", CLAUDE)
    assert_empty Quota.due_probes
    @now += 700
    assert_equal ["agy"], Quota.due_probes

    probed = []
    agent = Object.new.tap { |a| a.define_singleton_method(:ask_once) { |prompt, **| probed << prompt; prompt } }
    router = Object.new.tap { |r| r.define_singleton_method(:pool) { |wait: false| [] } }
    Master::CLI::Routing::ProviderCanary.new(agent:, router:).run

    assert_equal 1, probed.size
    refute Quota.dead?("agy:auto"), "the canary revived the lane"
    assert Quota.dead?("claude-cli:x")
  end

  def test_a_dead_lane_revives_at_its_deadline_without_the_operator
    Quota.note("claude-cli:x", CLAUDE)
    @now += 3 * 3600 - 1
    assert Quota.dead?("claude-cli:x")
    @now += 2
    refute Quota.dead?("claude-cli:x")
  end

  def test_state_survives_a_fresh_process
    Quota.clock = -> { Time.now.to_f }
    Quota.note("claude-cli:x", AGY)
    ruby = 'require "./lib/master"; Master::Io::LaneQuota.path = ARGV[0]; print Master::Io::LaneQuota.dead?("claude-cli:opus")'
    out, = Open3.capture2e(RbConfig.ruby, "-e", ruby, Quota.path, chdir: File.expand_path("..", __dir__))
    assert_equal "true", out.lines.last.to_s.strip
  end

  # Instrument check: the new lists are what assign, the role tails and the tiers read.
  def test_assign_reads_the_new_lists_and_lands_on_the_local_tail
    asked = []
    alive = ->(id) { asked << id; true }
    @lists.values.flatten.map { |m| Quota.lane_of(m) }.uniq.reject { |l| l == "ollama" }.each { |lane| Quota.note("#{lane}:x", CLAUDE) }

    picked = Roles.assign(env: {}, alive:)
    assert_equal %w[ollama:qwen2.5-coder:3b ollama:gemma3:4b ollama:gemma3:4b], [picked.critic, picked.fixer, picked.wisher], "critic is another model on the lane when no other provider lives"
    assert_equal @lists.values.flatten.uniq.select { |m| Quota.lane_of(m) == "ollama" }.first(1), asked.uniq.first(1)
    assert(asked.all? { |m| @lists.values.flatten.include?(m) }, "assign asked only about listed models")
    assert_match(/\Aonline: yes via ollama:gemma3:4b/, Health.line(@lists.values.flatten.uniq, refuses: ->(m) { Quota.dead?(m) }))
  end

  def test_with_everything_dead_the_status_line_says_so
    models = @lists.values.flatten.uniq
    models.map { |m| Quota.lane_of(m) }.uniq.each { |lane| Quota.note("#{lane}:x", AGY) }
    line = Health.line(models, refuses: ->(m) { Quota.dead?(m) })
    assert_match(/\Aonline: NO \(all lanes dead\) /, line)
    assert_match(/ollama: quota spent, back in 165h/, line)
    picked = Roles.assign(env: {}, alive: ->(_) { true })
    assert_nil picked.fixer
  end

  def test_every_list_and_tier_ends_in_a_local_model
    @lists.each { |role, models| assert Health.local_model?(models.last), "#{role} ends local" }
    tiers = Master.models_config.fetch("models")
    %w[default primary strong].each do |tier|
      assert Health.local_model?(tiers.fetch(tier).last.fetch("id")), "#{tier} ends local"
    end
  end

  def test_the_daemon_is_started_once_and_a_failed_start_is_not_repeated
    spawned = []
    probes = 0
    started = Health.ensure_ollama(base: "http://localhost:11434", up: ->(_) { (probes += 1) > 1 }, spawn: ->(b) { spawned << b }, binary: "ruby")
    assert_equal :started, started.state
    assert_equal ["ruby"], spawned

    Health.instance_variable_set(:@failed_at, nil)
    ticks = 0
    Health.clock = -> { ticks += 6 }
    failed = Health.ensure_ollama(base: "http://localhost:11434", up: ->(_) { false }, spawn: ->(b) { spawned << b }, binary: "ruby")
    assert_equal :failed, failed.state
    assert_match(/run it by hand/, failed.message)
    again = Health.ensure_ollama(base: "http://localhost:11434", up: ->(_) { false }, spawn: ->(b) { spawned << b }, binary: "ruby")
    assert_equal :failed, again.state
    assert_equal 2, spawned.size, "no second start inside a minute"
    assert_equal :failed, Health.ensure_ollama(base: "http://far.example:11434", up: ->(_) { false }, spawn: ->(*) { raise "no" }).state
  ensure
    Health.instance_variable_set(:@failed_at, nil)
    Health.clock = -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) }
  end
end
