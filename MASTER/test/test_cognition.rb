# frozen_string_literal: true

require_relative "test_helper"
require "tmpdir"
require "yaml"

# The cognitive layer, held to the two things that were wrong in its first draft
# and would each have made it look wired while doing nothing.
class TestCognition < Minitest::Test
  Cognition = Master::Cognition

  # A bus with the real glob semantics, because that is the fact under test:
  # EventBus compiles `*` to [^:]* and `**` to .*, so a single star sees only
  # colon-free event names.
  class Bus
    attr_reader :published

    def initialize
      @published = []
      @subscriptions = []
    end

    def subscribe(pattern, &block) = @subscriptions << [pattern, block]

    def publish(event, payload = {})
      enriched = payload.merge(event:)
      @published << enriched
      @subscriptions.each { |pattern, block| block.call(enriched) if glob?(pattern, event.to_s) }
      self
    end

    private

    def glob?(pattern, event)
      Regexp.new("\\A#{Regexp.escape(pattern).gsub('\\*\\*', ".*").gsub('\\*', "[^:]*")}\\z").match?(event)
    end
  end

  class Memory
    attr_reader :rows

    def initialize = @rows = []
    def remember(key, value, type:) = @rows << [key, value, type]
  end

  def test_state_built_from_the_frozen_default_is_still_mutable
    state = Cognition::State.new(Cognition::State::DEFAULT)
    state.affect["valence"] = 0.4
    state.drives["curiosity"] = 0.9

    assert_in_delta 0.4, state.affect["valence"]
    assert_in_delta 0.9, state.drives["curiosity"]
  end

  def test_attention_rises_with_prediction_error
    attention = Cognition::Attention.new
    affect = Cognition::State.new({}).affect
    low = attention.score(event: "event", payload: {}, prediction_error: 0.05, affect:)
    high = attention.score(event: "event", payload: {}, prediction_error: 1.0, affect:)

    assert_operator high, :>, low
  end

  # The bug that would have made the whole layer inert: `*` never matches a
  # colon-namespaced event, and nearly every event MASTER publishes has one.
  def test_the_subscription_reaches_namespaced_events
    Dir.mktmpdir("cognition") do |root|
      bus = Bus.new
      mind = Cognition::Mind.new(root:, bus:)
      bus.publish("tool:after", ok: true)

      assert_equal "tool:after", mind.snapshot.dig("self_model", "last_event"),
                   "a colon-namespaced event must reach the mind — `*` would not have"
    end
  end

  # Perception is silent and writes nothing; tick is the only writer and the
  # only publisher. A layer that published per observation would double every
  # event on a bus it subscribes to all of.
  def test_perception_neither_writes_nor_publishes
    Dir.mktmpdir("cognition") do |root|
      bus = Bus.new
      mind = Cognition::Mind.new(root:, bus:)
      bus.publish("chat:message", ok: true)

      refute_path_exists File.join(root, Cognition::Mind::STATE_PATH)
      assert_equal 1, bus.published.size, "observing must not put another event on the bus"

      mind.tick!

      assert_path_exists File.join(root, Cognition::Mind::STATE_PATH)
      assert(bus.published.any? { |row| row[:event] == "cognition:tick" })
    end
  end

  def test_observation_moves_affect_and_the_working_set
    Dir.mktmpdir("cognition") do |root|
      mind = Cognition::Mind.new(root:, bus: Bus.new)
      mind.observe(event: "chat:message", payload: { ok: true })
      snapshot = mind.snapshot

      assert_equal 1, snapshot.fetch("workspace").size
      assert_operator snapshot.dig("affect", "valence"), :>, 0, "a successful outcome raises valence"
    end
  end

  # The defect that made everything above moot: `tick!` had one caller in the
  # tree, at boot, once. So the workspace never decayed, continuity never moved,
  # nothing after the boot snapshot was written, and reflection could not fire —
  # `ticks` stopped at 1 and `1 % REFLECT_EVERY` is not zero. The layer perceived
  # for the life of the process and thought once, before anything had happened.
  # Perception paces the loop now, so this asserts the count threshold: the first
  # observations still write nothing, and the 256th ticks.
  def test_perception_paces_the_loop_it_used_to_leave_unrun
    Dir.mktmpdir("cognition") do |root|
      mind = Cognition::Mind.new(root:, bus: Bus.new)
      mind.observe(event: "tool:after", payload: { ok: true })

      assert_equal 0, mind.snapshot.fetch("ticks"), "one observation is not a tick"

      Cognition::Mind::TICK_EVERY_OBSERVATIONS.times { mind.observe(event: "tool:after") }

      assert_operator mind.snapshot.fetch("ticks"), :>, 0, "the loop must run without a caller"
      assert_path_exists File.join(root, Cognition::Mind::STATE_PATH)
    end
  end

  # Prediction error used to be recurrence: seconds since that event last fired,
  # off an instance variable that started empty every boot. So nothing MASTER had
  # ever seen informed what it expected. A learned transition is the difference —
  # a pair seen repeatedly stops being surprising, and Laplace keeps the second
  # sighting of a coincidence from scoring as certainty.
  def test_a_repeated_transition_stops_being_surprising
    model = Cognition::Prediction.new
    predictions = Cognition::State.new({}).predictions

    assert_in_delta 1.0, model.observe!(predictions, event: "chat:message")
    first = model.observe!(predictions, event: "tool:before")
    4.times { model.observe!(predictions, event: "chat:message"); model.observe!(predictions, event: "tool:before") }
    model.observe!(predictions, event: "chat:message")
    later = model.observe!(predictions, event: "tool:before")

    assert_in_delta 1.0, first, 0.001, "an unseen pair is fully surprising"
    assert_operator later, :<, 0.5, "a pair seen five times is expected"
    assert_equal "tool:before", model.expected(predictions, event: "chat:message")
  end

  # Correlated task streams prevent unrelated concurrent work from teaching one
  # another's event transitions.
  def test_prediction_streams_do_not_cross_train_different_tasks
    model = Cognition::Prediction.new
    predictions = Cognition::State.new({}).predictions

    6.times do
      model.observe!(predictions, event: "repair:start", context: "task-a")
      model.observe!(predictions, event: "test:pass", context: "task-a")
      model.observe!(predictions, event: "repair:start", context: "task-b")
      model.observe!(predictions, event: "test:fail", context: "task-b")
    end

    assert_equal "test:pass", model.expected(predictions, event: "repair:start", context: "task-a")
    assert_equal "test:fail", model.expected(predictions, event: "repair:start", context: "task-b")
    assert_nil model.expected(predictions, event: "repair:start"), "scoped evidence must not leak into the legacy stream"
    assert_operator predictions.fetch("streams").size, :<=, Cognition::Prediction::MAX_STREAMS
  end

  def test_walk_forward_evaluation_measures_task_scope_against_shared_stream
    training = []
    testing = []
    16.times do
      training.concat([
        { context: "task-a", event: "repair:start" },
        { context: "task-b", event: "repair:start" },
        { context: "task-a", event: "test:pass" },
        { context: "task-b", event: "test:fail" },
      ])
    end
    8.times do
      # The test stream presents each task contiguously, unlike training's
      # interleaved schedule. Contextual prediction should transfer; the shared
      # stream has learned the interleaving instead.
      testing.concat([
        { context: "task-a", event: "repair:start" },
        { context: "task-a", event: "test:pass" },
        { context: "task-b", event: "repair:start" },
        { context: "task-b", event: "test:fail" },
      ])
    end

    scoped = Cognition::Prediction.evaluate(training:, testing:, scoped: true)
    shared = Cognition::Prediction.evaluate(training:, testing:, scoped: false)

    assert_equal :measured, scoped[:state]
    assert_equal :walk_forward, scoped[:protocol]
    assert_equal 1.0, scoped[:top1_accuracy]
    assert_operator scoped[:top1_accuracy], :>, shared[:top1_accuracy]
    assert_equal 32, scoped[:attempts]
  end

  def test_walk_forward_evaluation_is_inconclusive_without_predictive_context
    report = Cognition::Prediction.evaluate(training: [], testing: [{ context: "task-a", event: "repair:start" }])

    assert_equal :inconclusive, report[:state]
    assert_nil report[:top1_accuracy]
  end

  def test_fix_loop_events_train_the_same_stream_and_record_observed_outcome
    Dir.mktmpdir("cognition-fix-outcome") do |root|
      bus = Bus.new
      mind = Cognition::Mind.new(root:, bus:)
      bus.publish("fix_loop:pass_start", run_id: "run-1", pass: 1, file_count: 4)
      bus.publish("fix_loop:terminal", task_id: "run-1", capability: "code_repair", ok: true, state: :done)
      assert File.file?(File.join(root, Cognition::Mind::STATE_PATH)),
             "a terminal repair outcome must flush cognition state immediately"

      snapshot = mind.snapshot
      predictor = Cognition::Prediction.new
      assert_equal "fix_loop:terminal", predictor.expected(
        snapshot.fetch("predictions"), event: "fix_loop:pass_start", context: "work:run-1"
      )
      stats = Cognition::SelfModel.new.performance(snapshot.fetch("self_model"), capability: "code_repair")
      assert_equal 1, stats[:attempts]
      assert_equal 1, stats[:successes]
    end
  end

  def test_mind_uses_task_context_for_prediction_streams
    Dir.mktmpdir("cognition-task-context") do |root|
      mind = Cognition::Mind.new(root:, bus: Bus.new)
      mind.observe(event: "repair:start", payload: { task_id: "task-a" })
      mind.observe(event: "test:pass", payload: { task_id: "task-a" })
      mind.observe(event: "repair:start", payload: { task_id: "task-b" })
      mind.observe(event: "test:fail", payload: { task_id: "task-b" })

      mind.tick!
      reloaded = Cognition::Mind.new(root:, bus: Bus.new)
      predictions = reloaded.snapshot.fetch("predictions")
      predictor = Cognition::Prediction.new
      assert_equal "test:pass", predictor.expected(predictions, event: "repair:start", context: "work:task-a")
      assert_equal "test:fail", predictor.expected(predictions, event: "repair:start", context: "work:task-b")
    end
  end

  def test_invalid_state_is_preserved_for_diagnosis
    Dir.mktmpdir("cognition-invalid-state") do |root|
      path = File.join(root, Cognition::Mind::STATE_PATH)
      FileUtils.mkdir_p(File.dirname(path))
      [
        "not: [valid",
        { "metrics" => "not-a-hash" }.to_yaml,
        { "predictions" => { "transitions" => { "chat" => "not-a-transition-table" } } }.to_yaml,
        { "workspace" => ["not-an-entry"] }.to_yaml,
        { "self_model" => { "performance" => { "bad name" => { "attempts" => 1 } } } }.to_yaml,
      ].each do |original|
        File.write(path, original)
        Cognition::Mind.new(root:, bus: Bus.new).tick!
        assert_equal original, File.read(path), "default state must not silently replace corrupt evidence"
      end
    end
  end

  def test_mind_persists_capability_outcomes_and_confidence_calibration
    Dir.mktmpdir("cognition-calibration") do |root|
      mind = Cognition::Mind.new(root:, bus: Bus.new)
      mind.observe(event: "repair:start", payload: { task_id: "repair-7" })
      mind.observe(event: "tool:after", payload: {
        task_id: "repair-7", capability: "code_repair", ok: true, predicted_confidence: 0.9
      })
      mind.tick!

      reloaded = Cognition::Mind.new(root:, bus: Bus.new)
      model = reloaded.snapshot.fetch("self_model")
      measured = Cognition::SelfModel.new.performance(model, capability: "code_repair")
      assert_equal 1, measured[:attempts]
      assert_equal 1, measured[:successes]
      assert_in_delta 0.9, measured[:mean_confidence]
      assert_in_delta 0.01, measured[:brier_score]
    end
  end

  def test_state_migrates_formula_driven_proxy_metrics
    state = Cognition::State.new({
      "identity" => { "continuity" => 1.0 },
      "metrics" => { "integration" => 0.9, "continuity" => 1.0 },
    })

    refute state.identity.key?("continuity")
    refute state.metrics.key?("continuity")
    refute state.metrics.key?("integration")
    assert state.metrics.key?("workspace_activity")
  end

  def test_state_restore_completeness_reports_source_shape_not_defaulted_shape
    Dir.mktmpdir("cognition-restore") do |root|
      path = File.join(root, "state.yml")
      File.write(path, { "identity" => { "name" => "MASTER" } }.to_yaml)

      restored = Cognition::State.load(path)
      assert_equal "restored", restored.load_status
      assert_operator restored.restore_completeness, :>, 0.0
      assert_operator restored.restore_completeness, :<, 1.0

      File.write(path, "not: [valid")
      invalid = Cognition::State.load(path)
      assert_equal "invalid", invalid.load_status
      assert_equal 0.0, invalid.restore_completeness
    end
  end

  # Unscoped observations remain restart-persistent for compatibility. They
  # represent temporal adjacency only, not causal evidence.
  def test_the_learned_expectation_survives_a_restart
    Dir.mktmpdir("cognition") do |root|
      first = Cognition::Mind.new(root:, bus: Bus.new)
      6.times { first.observe(event: "chat:message"); first.observe(event: "tool:before") }
      first.tick!

      reloaded = Cognition::Mind.new(root:, bus: Bus.new)

      assert_equal "tool:before",
                   Cognition::Prediction.new.expected(reloaded.snapshot.fetch("predictions"), event: "chat:message")
    end
  end

  # The working set is a competition. Keeping the twelve most RECENT let a burst
  # of routine events evict the surprising one that arrived before them, which is
  # the opposite of what a salience score is for.
  def test_the_working_set_keeps_the_most_salient_not_the_most_recent
    state = Cognition::State.new({})
    state.remember_workspace("key" => "loud", "salience" => 0.99, "event" => "tool:error", "at" => 0)
    20.times { |i| state.remember_workspace("key" => "quiet#{i}", "salience" => 0.1, "event" => "noise", "at" => i) }

    assert_equal Cognition::State::MAX_WORKSPACE, state.workspace.size
    assert_equal "loud", state.workspace.first["key"]
  end

  # The claim the layer must not make, pinned so nothing quietly upgrades it.
  def test_the_self_model_stays_uncertain_about_consciousness
    Dir.mktmpdir("cognition") do |root|
      memory = Memory.new
      mind = Cognition::Mind.new(root:, bus: Bus.new, memory:)
      text = mind.reflect!

      assert_includes text, "unknown about phenomenal consciousness"
      assert_equal 1, memory.rows.size
      assert_equal "general", memory.rows.first.last
    end
  end
end
