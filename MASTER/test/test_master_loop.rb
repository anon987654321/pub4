# frozen_string_literal: true

require_relative "test_helper"

class TestMasterLoop < Minitest::Test
  LOOP_ENVS = %w[MASTER_AUTOFIX MASTER_WATCH MASTER_WATCHER MASTER_HEARTBEAT MASTER_BACKGROUND MASTER_LOOP].freeze

  def with_clean_env
    saved = LOOP_ENVS.to_h { |key| [key, ENV[key]] }
    LOOP_ENVS.each { |key| ENV.delete(key) }
    yield
  ensure
    LOOP_ENVS.each { |key| saved[key].nil? ? ENV.delete(key) : ENV[key] = saved[key] }
  end

  def test_master_loop_fix_enables_autofix_only
    with_clean_env do
      ENV["MASTER_LOOP"] = "fix"
      Master.apply_master_loop!
      assert_equal "1", ENV["MASTER_AUTOFIX"]
      assert_equal "0", ENV["MASTER_WATCH"]
      assert_equal "0", ENV["MASTER_WATCHER"]
    end
  end

  # Building the runtime must not start the fix loop, which sleeps STARTUP_DELAY
  # and then rewrites lib/ in the background. MASTER_AUTOFIX=1 is the only key;
  # process defaults set it to 0 and MASTER_LOOP=fix is how a person asks.
  def test_build_starts_the_fix_loop_only_when_autofix_is_asked_for
    started = []
    fake_loop = Object.new
    build = lambda do
      Master::Fix::FixLoop.stub(:new, fake_loop) do
        Master::Builder.stub(:start_fix_loop_background, ->(loop, **) { started << loop }) do
          Master::Builder.build_fix_loop(root: Master::ROOT, infra: {}, agent: nil, scanner: nil, axioms: nil,
                                         rules: nil, learnings: nil, bus: nil, git: nil)
        end
      end
    end

    with_clean_env do
      assert_equal "0", Master::MasterRuntime::PROCESS_DEFAULTS["MASTER_AUTOFIX"]
      build.call
      assert_empty started, "an unset MASTER_AUTOFIX starts nothing"
      ENV["MASTER_AUTOFIX"] = "0"
      build.call
      assert_empty started

      ENV["MASTER_AUTOFIX"] = "1"
      build.call
      assert_equal [fake_loop], started
    end
  end

  # MASTER_INCREMENTAL=1 is the only way the boot builds an incremental fix loop.
  def test_incremental_reaches_the_fix_loop_only_when_set
    seen = []
    build = lambda do
      Master::Fix::FixLoop.stub(:new, ->(**kwargs) { seen << kwargs[:incremental] }) do
        Master::Builder.build_fix_loop(root: Master::ROOT, infra: {}, agent: nil, scanner: nil, axioms: nil,
                                       rules: nil, learnings: nil, bus: nil, git: nil)
      end
    end

    with_env("MASTER_INCREMENTAL" => nil, "MASTER_AUTOFIX" => nil) { build.call }
    with_env("MASTER_INCREMENTAL" => "1", "MASTER_AUTOFIX" => nil) { build.call }

    assert_equal [false, true], seen
  end

  # MASTER_WATCH=1 builds the watch loop and runs it on a watched thread.
  def test_watch_starts_the_watch_loop_only_when_set
    started = []
    watch_loop = Object.new
    build = lambda do
      Master::Fix::WatchLoop.stub(:new, watch_loop) do
        Master::Builder.stub(:watched_thread, ->(_bus, where) { started << where }) do
          Master::Builder.build_watch_loop(rules: nil, agent: nil, scanner: nil, root: Master::ROOT, bus: nil, learnings: nil)
        end
      end
    end

    assert_nil with_env("MASTER_WATCH" => nil) { build.call }
    assert_same watch_loop, with_env("MASTER_WATCH" => "1") { build.call }
    assert_equal ["watch_loop"], started
  end

  # Full constitutional self-test is an explicit boot diagnostic. The same test remains
  # available through `rake selftest` and the heartbeat job without making the critical
  # application startup path scan every repository law on every launch.
  def test_strict_boot_is_explicitly_opt_in
    with_env("MASTER_STRICT_BOOT" => nil) do
      refute Master::Builder.strict_boot_requested?
    end
    with_env("MASTER_STRICT_BOOT" => "0") do
      refute Master::Builder.strict_boot_requested?
    end
    with_env("MASTER_STRICT_BOOT" => "1") do
      assert Master::Builder.strict_boot_requested?
    end
  end

  def test_fix_loop_builder_contract_has_no_retired_rollback_dependency
    parameters = Master::Fix::FixLoop.instance_method(:build_pass_runner).parameters
    assert_empty parameters.select { |kind, name| kind == :keyreq && name == :rollback }
  end

  def test_boot_self_test_is_opt_in
    ran = []
    self_test = Object.new
    self_test.define_singleton_method(:call) { ran << :self_test }
    ledger = Object.new
    ledger.define_singleton_method(:attach) { nil }
    standing = Object.new
    standing.define_singleton_method(:wire_container) { |**| nil }
    finalize = lambda do
      Master::Trace::Ledger::Feedback.stub(:new, ledger) do
        Master::Trace::Ledger::Reflexion.stub(:new, ledger) do
          Master::Review::Scan::SelfTest.stub(:new, ->(**) { self_test }) do
            Master::Builder.stub(:publish_self_test, nil) do
              Master::Builder.finalize_ai_boot(bus: nil, root: Master::ROOT, infra: {}, agent: nil,
                                               autonomous: { standing:, learnings: nil }, scanner: nil, lean_boot: true)
            end
          end
        end
      end
    end

    with_env("MASTER_BOOT_SELF_TEST" => nil) { finalize.call }
    assert_empty ran
    with_env("MASTER_BOOT_SELF_TEST" => "1") { finalize.call }
    assert_equal [:self_test], ran
  end

  def with_env(pairs)
    saved = pairs.keys.to_h { |key| [key, ENV[key]] }
    pairs.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
    yield
  ensure
    saved.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
  end

  # The early-boot mode map and data/limits.yml#process are the same fact in two
  # places; this pins them so heartbeat->env and the "fix"/"autofix" alias cannot
  # drift the way they had ("MASTER_BACKGROUND" vs "MASTER_HEARTBEAT").
  def test_loop_flags_agree_with_process_yaml
    from_yaml = Master::Ops::ProcessBudget.env_by_loop
                     .transform_keys { |name| name == "autofix" ? "fix" : name }
    assert_equal from_yaml, Master::MasterRuntime::LOOP_FLAGS
  end

  def test_model_accessors_do_not_cache_across_roots
    Dir.mktmpdir do |workspace|
      one = File.join(workspace, "one", "data")
      two = File.join(workspace, "two", "data")
      FileUtils.mkdir_p(one)
      FileUtils.mkdir_p(two)
      File.write(File.join(one, "models.yml"), "openrouter:\n  default_model: one-default\nmodels:\n  grok_primary:\n    - id: one-model\n")
      File.write(File.join(two, "models.yml"), "openrouter:\n  default_model: two-default\nmodels:\n  grok_primary:\n    - id: two-model\n")

      assert_equal "one-default", Master::MasterRuntime.openrouter_default(root: workspace + "/one")
      assert_equal "two-default", Master::MasterRuntime.openrouter_default(root: workspace + "/two")
      assert_equal "one-model", Master::MasterRuntime.free_primary_model(root: workspace + "/one")
      assert_equal "two-model", Master::MasterRuntime.free_primary_model(root: workspace + "/two")
    end
  end

  def test_common_data_readers_resolve_the_declared_registries
    assert_kind_of Hash, Master.models_config
    assert_kind_of Hash, Master.patterns_config
    assert_kind_of Hash, Master.soul_config
    assert_kind_of Array, Master.soul_config.dig("absolute", "sacred_paths")
  end

  def test_models_config_is_the_single_models_registry_reader
    config = Master.models_config(root: Master::ROOT)
    assert config.key?("models")
    assert_equal config, Master.models_config(root: Master::ROOT)
  end

  def test_limits_and_state_resolve_to_their_files
    assert File.exist?(Master.limits_path)
    assert Master.limits_path.end_with?("limits.yml")
    assert File.exist?(Master.state_path)
    refute File.exist?(Master.data_path("style.yml"))
    refute File.exist?(Master.data_path("operator_principles.yml"))
    assert File.exist?(Master.data_path("laws.yml"))
    assert Master.law("style").key?("typography")
    assert Master.tokens.key?("worn_type")
  end

  # The operator's standing orders live in soul.yml, not in the catalogue the
  # file scanner reads. They govern how to work rather than what source text may
  # look like, so no detector can match one, and laws.yml offered them a shape
  # with a severity and a tier they could never use. soul reaches the prompt
  # whole through PersonalityPromptBuilder#add_rules; Ground::Constitution cut
  # them to 480 characters, which took 358 off FLAT_HIERARCHY alone.
  def test_operator_conduct_is_a_rule_like_any_other
    rules = Master::Ground::Laws.new.rules

    %w[OPERATOR_AUTONOMY EXECUTE_NOT_INSTRUCT SHELL_DISCIPLINE VPS_SERIAL_TRUTH NO_NEW_FILES
       STRUNK_WHITE FLAT_PIXELS VOICE_TERSE_UNIX MICRO_REFINEMENTS].each do |id|
      assert rules.key?(id), "#{id} binds conduct and must still be a rule"
    end

    refute Master.load_laws.key?("operator_principles"),
           "conduct in laws.yml is a rule no detector can ever match"
    refute Master.load_yaml(Master.data_path("soul.yml")).fetch("absolute").key?("rules"),
           "one registry: law/, not soul"
  end

  def test_council_prompts_load_from_council_yml
    prompts = Master::Review::Council::Deliberation.prompts
    assert prompts["judge"].to_s.include?("Council judge")
    assert prompts["juror"].to_s.include?("persona_name")
  end
end
