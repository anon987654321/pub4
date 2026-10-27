# frozen_string_literal: true

require_relative "test_helper"

class TestRepairLoopPolicy < Minitest::Test
  Rule = Struct.new(:id, :severity)

  class FakeBus
    attr_reader :events

    def initialize
      @events = []
    end

    def publish(event, payload = {})
      @events << [event, payload]
    end
  end

  class Scanner
    attr_reader :deletions_asked

    def initialize(allow_autofix: true)
      @allow_autofix = allow_autofix
      @deletions_asked = []
    end

    def scan(_path, laws: nil)
      Master::Result.ok([{ law: "TEST_RULE", severity: :warning, line: 1, message: "fix me" }])
    end

    # The keyword mirrors Fix::Scanner. A double that takes fewer
    # arguments than the object it stands for reports a signature the tree does
    # not have, and four tests here read :error for that reason alone.
    def should_autofix?(_rule_id, _confidence, allow_deletions: false)
      @deletions_asked << allow_deletions
      @allow_autofix
    end
  end

  class RecordingScanner
    attr_reader :paths

    def initialize
      @paths = []
    end

    def scan(path, laws: nil)
      @paths << path
      source = File.read(path)
      findings = Array.new(source.scan("violation").size) do |index|
        { law: "TEST_RULE", severity: :warning, line: index + 1, message: "fix me" }
      end
      Master::Result.ok(findings)
    end
  end

  class Agent
    attr_reader :calls

    def initialize(error: nil)
      @error = error
      @calls = 0
    end

    def ask(_prompt)
      @calls += 1
      raise @error if @error
      "UNCHANGED"
    end
  end

  # apply passed `encoding:` to write_atomic, which takes no such keyword, so
  # every model fix raised at the write, was logged as a write error, and
  # nothing a model proposed was ever applied.
  def test_measurement_only_finding_is_not_sent_to_the_model
    Dir.mktmpdir do |root|
      path = File.join(root, "sample.rb")
      File.write(path, "puts :x\\n")
      scanner = Object.new
      scanner.define_singleton_method(:scan) do |_path, laws: nil|
        Master::Result.ok([{ law: "CQS", severity: :warning, line: 1, message: "measured" }])
      end
      agent = Agent.new
      loop = build_loop(root:, bus: FakeBus.new, scanner:, agent:)

      result = loop.run_once([path])

      assert_equal :clean, result[:status]
      assert_equal 0, agent.calls
    end
  end

  def test_repair_routing_uses_live_operation_aware_model_selection
    agent = Object.new
    calls = []
    agent.define_singleton_method(:model_for) do |operation:|
      calls << operation
      operation.to_sym == :file_write ? "grok-cli:auto" : "ollama:glm-5.3-flash:cloud"
    end

    loop = Master::Fix::RepairLoop.allocate
    loop.instance_variable_set(:@agent, agent)
    selected = loop.send(:routing_model_ids)

    assert_equal({ strong: "grok-cli:auto", fast: "ollama:glm-5.3-flash:cloud" }, selected)
    assert_equal %i[file_write code_generation], calls
  end

  def test_visual_custody_is_limited_to_frontend_rails_sources
    loop = Master::Fix::RepairLoop.allocate

    assert loop.send(:visual_source?, "/repo/RAILS/brgen/app/assets/stylesheets/application.scss")
    assert loop.send(:visual_source?, "/repo/RAILS/brgen/app/views/home/index.html.erb")
    refute loop.send(:visual_source?, "/repo/RAILS/brgen/app/models/post.rb")
    refute loop.send(:visual_source?, "/repo/RAILS/master/public/face.css")
  end

  def test_an_accepted_fix_is_written
    Dir.mktmpdir do |root|
      path = File.join(root, "sample.rb")
      File.write(path, "violation\n")
      bus = FakeBus.new
      loop = build_loop(root:, bus:, scanner: RecordingScanner.new, agent: Agent.new)

      applied = loop.send(:apply, path, "clean\n", { law: "TEST_RULE", file: path, line: 1 })

      assert applied, "the fix was not applied: #{bus.events.last.inspect}"
      assert_equal "clean\n", File.read(path)
      refute_includes bus.events.map(&:first), "repair_loop:write_error"
    end
  end

  # A rescan says the rule stopped firing; the file's own test says whether the
  # behaviour survived. A fix its test rejects is rolled back.
  def test_a_fix_its_own_test_rejects_is_rolled_back
    Dir.mktmpdir do |root|
      path = File.join(root, "sample.rb")
      File.write(path, "violation\n")
      FileUtils.mkdir_p(File.join(root, "test"))
      File.write(File.join(root, "test", "test_sample.rb"),
                 %(exit(File.read(File.join(__dir__, "..", "sample.rb")).include?("kept") ? 0 : 1)\n))
      bus = FakeBus.new
      loop = build_loop(root:, bus:, scanner: RecordingScanner.new, agent: Agent.new)
      violation = { law: "TEST_RULE", file: path, line: 1 }

      refute loop.send(:apply, path, "clean\n", violation), "a fix its test fails must not stand"
      assert_equal "violation\n", File.read(path)
      rejected = bus.events.find { |event, _| event == "repair_loop:fix_rejected" }
      assert_equal "test_failed", rejected&.last&.fetch(:reason)

      assert loop.send(:apply, path, "kept\n", violation), "a fix its test passes stands"
      assert_equal "kept\n", File.read(path)
    end
  end

  class BrokenRuleScanner
    def scan(_path, laws: nil)
      Master::Result.err("scanner unavailable", category: :infrastructure)
    end
  end

  def test_repair_loop_scan_failure_is_not_clean
    Dir.mktmpdir do |root|
      path = File.join(root, "sample.rb")
      File.write(path, "puts :x\n")
      loop = build_loop(root:, bus: FakeBus.new, scanner: BrokenRuleScanner.new, agent: Agent.new)

      result = loop.run_once([path])

      assert_equal :error, result[:status]
      assert_equal 1, result[:breakdown][:error]
    end
  end

  def test_missing_model_is_a_named_outcome
    Dir.mktmpdir do |root|
      path = File.join(root, "sample.rb")
      File.write(path, "puts :x
")
      loop = build_loop(root:, bus: FakeBus.new, scanner: Scanner.new, agent: nil)

      result = loop.run_once([path])

      assert_equal :model_unavailable, result[:breakdown].keys.find { |key| key.to_s == "model_unavailable" }
      assert_equal 0, result[:fixed]
    end
  end

  def test_prediction_engine_can_skip_autofix
    Dir.mktmpdir do |root|
      path = File.join(root, "sample.rb")
      File.write(path, "puts :x\n")
      bus = FakeBus.new
      agent = Agent.new
      loop = build_loop(root:, bus:, scanner: Scanner.new(allow_autofix: false), agent:)

      result = loop.run_once([path])

      assert_equal 0, result[:fixed]
      assert_equal 0, agent.calls
      assert_includes bus.events.map(&:first), "repair_loop:autofix_skipped"
    end
  end

  # A confidence-gated skip was never actually attempted -- recording it as
  # :stuck (same as a genuine failed fix) would silently poison that rule's
  # fix_quality every time the check fires, deprioritizing it further with no
  # real defect behind it (the OpenCrabs feedback_policy.rs lesson).
  class RecordingLearnings
    attr_reader :calls

    def initialize
      @calls = []
    end

    def record(**kwargs)
      @calls << kwargs
    end
  end

  def test_file_repair_only_remembers_rules_it_can_actually_attempt
    finding = { law: "TEST_RULE", severity: :warning, line: 1, message: "fix me" }
    repair = Master::Fix::FileRepair.allocate
    repair.instance_variable_set(:@findings, [finding])
    repair.define_singleton_method(:repairable) { [] }

    assert_empty repair.asked_rules
  end

  def test_confidence_skip_records_skipped_not_stuck
    Dir.mktmpdir do |root|
      path = File.join(root, "sample.rb")
      File.write(path, "puts :x\n")
      learnings = RecordingLearnings.new
      loop = Master::Fix::RepairLoop.new(
        law: Rule.new("TEST_RULE", :warning),
        agent: Agent.new,
        scanner: Scanner.new(allow_autofix: false),
        root:,
        bus: FakeBus.new,
        learnings:,
      )

      result = loop.run_once([path])

      assert_equal :skipped, result[:status]
      assert_equal [{ law: "TEST_RULE", file_type: "rb", outcome: :skipped }], learnings.calls
    end
  end

  def test_permanent_failure_uses_fail_fast_branch
    Dir.mktmpdir do |root|
      path = File.join(root, "sample.rb")
      File.write(path, "puts :x\n")
      bus = FakeBus.new
      agent = Agent.new(error: RuntimeError.new("permission denied"))
      loop = build_loop(root:, bus:, scanner: Scanner.new, agent:)

      result = loop.run_once([path])

      assert_equal :stuck, result[:status]
      assert_includes bus.events.map(&:first), "repair_loop:fail_fast"
    end
  end

  def test_ambiguous_failure_requests_human_intervention
    Dir.mktmpdir do |root|
      path = File.join(root, "sample.rb")
      File.write(path, "puts :x\n")
      bus = FakeBus.new
      agent = Agent.new(error: RuntimeError.new("partial write detected"))
      loop = build_loop(root:, bus:, scanner: Scanner.new, agent:)

      result = loop.run_once([path])

      assert_equal :stuck, result[:status]
      assert_includes bus.events.map(&:first), "repair_loop:human_intervention"
    end
  end

  def test_preamble_loads_soul_once_across_repair_loops
    original = Master.method(:load_yaml)
    count = 0
    Master::Fix::RepairLoop.clear_preamble_cache!
    Master.define_singleton_method(:load_yaml) do |path, symbolize_names: false, default: {}|
      if path.end_with?("soul.yml")
        count += 1
        { "absolute" => { "golden_law" => "CACHE_ME" } }
      else
        original.call(path, symbolize_names:, default:)
      end
    end

    Dir.mktmpdir do |root|
      first = build_loop(root:, bus: FakeBus.new, scanner: Scanner.new, agent: Agent.new)
      second = build_loop(root:, bus: FakeBus.new, scanner: Scanner.new, agent: Agent.new)
      count = 0

      assert_includes first.__send__(:preamble), "CACHE_ME"
      assert_includes second.__send__(:preamble), "CACHE_ME"
      assert_operator count, :<=, 1, "soul.yml should load at most once per preamble cache"
    end
  ensure
    Master.define_singleton_method(:load_yaml) do |path, symbolize_names: false, default: {}|
      original.call(path, symbolize_names:, default:)
    end
    Master::Fix::RepairLoop.clear_preamble_cache!
  end

  def test_rescan_candidate_preserves_original_file_extension
    Dir.mktmpdir do |root|
      path = File.join(root, "sample.rb")
      File.write(path, "violation\n")
      scanner = RecordingScanner.new
      loop = build_loop(root:, bus: FakeBus.new, scanner:, agent: Agent.new)

      count = loop.__send__(:rescan_candidate, "clean\n", path)

      assert_equal 0, count
      assert_equal ".rb", File.extname(scanner.paths.last)
    end
  end

  def test_best_candidate_requires_rescanning_even_for_one_candidate
    Dir.mktmpdir do |root|
      path = File.join(root, "sample.rb")
      File.write(path, "violation\n")
      scanner = RecordingScanner.new
      loop = build_loop(root:, bus: FakeBus.new, scanner:, agent: Agent.new)

      best = loop.__send__(:best_candidate, ["clean\n"], path)

      assert_equal "clean\n", best
      assert_operator scanner.paths.size, :>=, 2, "baseline and candidate must both be measured"
    end
  end

  def test_best_candidate_rejects_candidates_that_increase_violations
    Dir.mktmpdir do |root|
      path = File.join(root, "sample.rb")
      File.write(path, "violation\n")
      scanner = RecordingScanner.new
      loop = build_loop(root:, bus: FakeBus.new, scanner:, agent: Agent.new)

      best = loop.__send__(:best_candidate, %W[violation\nviolation\n clean\n], path)

      assert_equal "clean\n", best
    end
  end

  def test_best_candidate_rejects_unavailable_mapped_simulation_evidence
    Dir.mktmpdir do |root|
      path = File.join(root, "sample.rb")
      File.write(path, "violation\n")
      bus = FakeBus.new
      loop = build_loop(root:, bus:, scanner: RecordingScanner.new, agent: Agent.new)
      simulation = Object.new
      simulation.define_singleton_method(:evaluate_candidates) do |**|
        [{
          status: :unavailable,
          reason: "test runner unavailable",
          test_paths: ["test/test_sample.rb"],
          regressions: [],
          improvements: [],
        }]
      end
      loop.define_singleton_method(:user_simulation) { simulation }

      assert_nil loop.__send__(:best_candidate, ["clean\n"], path)
      rejected = bus.events.find { |event, _| event == "repair_loop:candidate_rejected" }
      assert_equal "repair_loop:candidate_rejected", rejected&.first
      assert_match(/simulation unavailable: test runner unavailable/, rejected.last.fetch(:reason))
      assert_includes bus.events.map(&:first), "repair_loop:candidate_selection_blocked"
    end
  end

  def test_best_candidate_marks_no_test_fallback_as_unverified
    Dir.mktmpdir do |root|
      path = File.join(root, "sample.rb")
      File.write(path, "violation\n")
      bus = FakeBus.new
      loop = build_loop(root:, bus:, scanner: RecordingScanner.new, agent: Agent.new)
      simulation = Object.new
      simulation.define_singleton_method(:evaluate_candidates) do |**|
        [{
          status: :unavailable,
          reason: "no focused test path exists for this surface",
          test_paths: [],
          regressions: [],
          improvements: [],
        }]
      end
      loop.define_singleton_method(:user_simulation) { simulation }

      assert_equal "clean\n", loop.__send__(:best_candidate, ["clean\n"], path)
      selected = bus.events.find { |event, _| event == "repair_loop:candidate_selected_unverified" }
      assert_equal :unavailable, selected.last.fetch(:status)
      assert_empty selected.last.fetch(:tests)
      assert_match(/no focused test path/, selected.last.fetch(:reason))
      refute_includes bus.events.map(&:first), "repair_loop:candidate_selected"
    end
  end

  def test_best_candidate_rejects_a_missing_simulation_result
    Dir.mktmpdir do |root|
      path = File.join(root, "sample.rb")
      File.write(path, "violation\n")
      bus = FakeBus.new
      loop = build_loop(root:, bus:, scanner: RecordingScanner.new, agent: Agent.new)
      simulation = Object.new
      simulation.define_singleton_method(:evaluate_candidates) { |**| [] }
      loop.define_singleton_method(:user_simulation) { simulation }

      assert_nil loop.__send__(:best_candidate, ["clean\n"], path)
      rejected = bus.events.find { |event, _| event == "repair_loop:candidate_rejected" }
      assert_match(/candidate has no simulation result/, rejected.last.fetch(:reason))
    end
  end

  def test_best_candidate_rejects_blocked_simulation
    Dir.mktmpdir do |root|
      path = File.join(root, "sample.rb")
      File.write(path, "violation\n")
      bus = FakeBus.new
      loop = build_loop(root:, bus:, scanner: RecordingScanner.new, agent: Agent.new)
      simulation = Object.new
      simulation.define_singleton_method(:evaluate_candidates) do |**|
        [{
          status: :blocked,
          reason: "runner launch refused",
          test_paths: ["test/test_sample.rb"],
          regressions: [],
          improvements: [],
        }]
      end
      loop.define_singleton_method(:user_simulation) { simulation }

      assert_nil loop.__send__(:best_candidate, ["clean\n"], path)
      refute_includes bus.events.map(&:first), "repair_loop:candidate_selected"
      assert_includes bus.events.map(&:first), "repair_loop:candidate_selection_blocked"
    end
  end

  class BrokenRescanScanner < RecordingScanner
    def scan(path, laws: nil)
      @paths << path
      Master::Result.err("rescan unavailable", category: :infrastructure)
    end
  end

  def test_best_candidate_rejects_all_candidates_when_rescan_fails
    Dir.mktmpdir do |root|
      path = File.join(root, "sample.rb")
      File.write(path, "violation\n")
      loop = build_loop(root:, bus: FakeBus.new, scanner: BrokenRescanScanner.new, agent: Agent.new)

      assert_nil loop.__send__(:best_candidate, ["clean\n"], path)
    end
  end

  # Regression: `return match[1].strip if (match = text.match(...))` raised
  # NameError every time the regex actually matched -- Ruby's parser hadn't
  # seen the `match =` assignment yet at the point `match[1]` is read
  # (textually earlier on the same line), so it tried to call a `match`
  # method instead of using the local var. This meant extract_code crashed
  # on every LLM response containing a real fenced code block -- the normal
  # case -- silently swallowed by the callers' rescue StandardError, so
  # genetic_fix/architect_then_fix degraded to whole_file_fallback (or
  # exhausted retries) even when the LLM behaved correctly.
  class ScriptedAgent
    def initialize(reply) = @reply = reply
    def ask(_prompt) = @reply
    def ask_once(_prompt, **) = @reply.respond_to?(:call) ? @reply.call : @reply
  end

  def verdict_for(reply)
    Dir.mktmpdir do |root|
      path = File.join(root, "sample.rb")
      File.write(path, "puts :x\n")
      loop = build_loop(root:, bus: FakeBus.new, scanner: Scanner.new, agent: ScriptedAgent.new(reply))
      loop.send(:reflexion_verify, { law: "TEST_RULE", file: path, line: 1, message: "fix me" }, "puts :y\n")
    end
  end

  # Only SAFE approves. A ramble or a check that raised approved the fix before,
  # and with fixes now reaching the disk that is a fix nobody reviewed.
  def test_reflexion_approves_only_on_safe
    assert_equal "puts :y\n", verdict_for("SAFE")
    assert_nil verdict_for("UNSAFE: drops a branch")
    assert_nil verdict_for("I think this looks reasonable overall.")
    assert_nil verdict_for(-> { raise "provider down" })
  end

  # The verifier saw the first 600 characters of each version, so a fix deep
  # in a file was invisible and every one was refused as byte-identical.
  def test_reflexion_is_shown_a_change_made_deep_in_the_file
    original = (1..200).map { |n| "line_#{n} = #{n}\n" }.join
    proposed = original.sub("line_150 = 150", "line_150 = :fixed")
    prompt = build_loop(root: Dir.pwd, bus: FakeBus.new, scanner: Scanner.new, agent: ScriptedAgent.new("SAFE"))
               .send(:reflexion_prompt, { law: "TEST_RULE", line: 150, message: "fix me" }, original, proposed)

    assert_includes prompt, "-line_150 = 150"
    assert_includes prompt, "+line_150 = :fixed"
    refute_includes prompt, "line_1 = 1\n", "unchanged lines far from the fix stay out"
  end

  # The verifier cannot read files: a changed signature carries its callers, and a partial
  # repair of a group is judged on correctness, not on fixing every finding.
  def test_reflexion_sees_the_callers_of_a_changed_signature
    original = "def zz_reflexion_probe(lines, path)\n  lines\nend\n"
    proposed = "def zz_reflexion_probe(lines, path:)\n  lines\nend\n"
    finding = { law: "FEW_ARGUMENTS", line: 1, message: "two positional" }
    prompt = build_loop(root: Dir.pwd, bus: FakeBus.new, scanner: Scanner.new, agent: ScriptedAgent.new("SAFE"))
               .send(:reflexion_prompt, finding, original, proposed)

    assert_includes prompt, "Callers of zz_reflexion_probe, whose parameters changed"
    assert_includes prompt, "Judge correctness, not completeness"
  end

  # The operator allowed snapping an off-scale value to the nearest token (2026-10-27): the
  # verifier is told the visible change is intended, and other findings are judged as before.
  def test_a_scale_finding_may_snap_to_its_nearest_token
    loop = build_loop(root: Dir.pwd, bus: FakeBus.new, scanner: Scanner.new, agent: ScriptedAgent.new("SAFE"))
    scale = { law: "LINE_HEIGHT_ON_SCALE+SMALL_FILES", line: 4, message: "line-height 1.35 off scale" }
    other = { law: "FEW_ARGUMENTS", line: 4, message: "three positional" }

    assert_includes loop.send(:reflexion_prompt, scale, "a\n", "b\n"), "do not refuse it for altering rendering"
    refute_includes loop.send(:reflexion_prompt, other, "a\n", "b\n"), "altering rendering"
    assert_includes loop.send(:scale_snap_rule, scale), "var(--leading-*)"
  end

  # git's diff arrives as BINARY. A non-ASCII line in it raised inside the UTF-8
  # prompt, and the refusal that followed killed every such repair unread.
  def test_reflexion_reads_a_change_beside_non_ascii_text
    original = "# Søknad — kø\nvalue = 1\n"
    proposed = original.sub("value = 1", "value = 2")
    prompt = build_loop(root: Dir.pwd, bus: FakeBus.new, scanner: Scanner.new, agent: ScriptedAgent.new("SAFE"))
               .send(:reflexion_prompt, { law: "TEST_RULE", line: 2, message: "fix — me" }, original, proposed)

    assert_includes prompt, "# Søknad — kø"
    assert_includes prompt, "+value = 2"
  end

  # The fallback returned the model's raw reply, prose and fences included, or
  # the literal UNCHANGED, and apply wrote that over the source.
  def test_the_whole_file_fallback_returns_code_or_nothing
    Dir.mktmpdir do |root|
      path = File.join(root, "sample.rb")
      File.write(path, "puts :x\n")
      violation = { law: "TEST_RULE", file: path, line: 1, message: "fix me" }
      fenced = build_loop(root:, bus: FakeBus.new, scanner: Scanner.new, agent: ScriptedAgent.new("Here:\n```ruby\nputs :y\n```\n"))
      unchanged = build_loop(root:, bus: FakeBus.new, scanner: Scanner.new, agent: ScriptedAgent.new("UNCHANGED"))

      assert_equal "puts :y\n", fenced.send(:whole_file_fallback, violation:, src: "puts :x\n", path:, reason: "test")
      assert_nil unchanged.send(:whole_file_fallback, violation:, src: "puts :x\n", path:, reason: "test")
    end
  end

  def test_extract_code_handles_fenced_response_without_nameerror
    Dir.mktmpdir do |root|
      loop = build_loop(root:, bus: FakeBus.new, scanner: Scanner.new, agent: Agent.new)

      result = loop.__send__(:extract_code, "here is the fix:\n```ruby\nputs 1\n```\n", ".rb")

      assert_equal "puts 1\n", result
    end
  end

  def test_extract_code_passes_through_unfenced_response
    Dir.mktmpdir do |root|
      loop = build_loop(root:, bus: FakeBus.new, scanner: Scanner.new, agent: Agent.new)

      result = loop.__send__(:extract_code, "plain response, no code fence")

      assert_equal "plain response, no code fence\n", result
    end
  end

# A reply that is a tool call, not a verdict, is asked for again with the diff stated as the whole
# change; the second answer decides. Only SAFE approves either way.
def test_a_verdictless_reply_is_asked_for_again_once
  replies = ["<invoke name=\"ReadFile\">", "SAFE"]
  assert_equal "puts :y\n", verdict_for(-> { replies.shift })
  replies = ["<invoke name=\"ReadFile\">", "still thinking aloud"]
  assert_nil verdict_for(-> { replies.shift })
  assert_equal 0, replies.size
end

def test_a_nonverdict_is_logged_as_no_verdict_not_as_unsafe
  loop = Master::Fix::RepairLoop.allocate
  Thread.current[:reflexion_reason] = nil

  assert_nil loop.send(:handle_reflexion_response, "<invoke name=\"ReadFile\">", "f.rb", "src")
  assert_match(/\Ano verdict from the reviewer/, Thread.current[:reflexion_reason])
ensure
  Thread.current[:reflexion_reason] = nil
end

  # The verifier answers "UNSAFE: <reason>"; the reason has to reach the rejection line, not
  # only a bus event nobody reads.
  def test_a_reflexion_refusal_keeps_the_verifiers_reason_for_the_log
    loop = Master::Fix::RepairLoop.allocate
    Thread.current[:reflexion_reason] = nil

    assert_nil loop.send(:handle_reflexion_response, "UNSAFE: the guard clause is dropped", "f.rb", "src")
    assert_equal "UNSAFE: the guard clause is dropped", Thread.current[:reflexion_reason]
    assert_equal "src", loop.send(:handle_reflexion_response, "SAFE", "f.rb", "src")
  ensure
    Thread.current[:reflexion_reason] = nil
  end

  # This drives the complete one-file repair path, not only the private apply helper.
  # The temporary target has no campaign surface of its own, so candidate selection
  # must remain explicitly unverified while the enclosing test verifies the repair.
  class RepairAndVerifyAgent
    def ask(prompt)
      response_for(prompt)
    end

    def ask_once(prompt, **)
      response_for(prompt)
    end

    private

    def response_for(prompt)
      prompt.include?("Verify this proposed code fix is correct.") ? "SAFE" : "clean\n"
    end
  end

  def test_RI_341_fix_repairs_known_small_defect_and_verifies
    previous_scan_agreement = ENV["MASTER_FIX_SCAN_AGREEMENT"]
    ENV["MASTER_FIX_SCAN_AGREEMENT"] = "0"
    Dir.mktmpdir("master-fix-known-defect") do |root|
      path = File.join(root, "sample.rb")
      File.write(path, "violation\n")
      bus = FakeBus.new
      scanner = RecordingScanner.new
      scanner.define_singleton_method(:should_autofix?) do |_rule_id, _confidence, allow_deletions: false|
        true
      end
      loop = build_loop(root:, bus:, scanner:, agent: RepairAndVerifyAgent.new)

      result = loop.run_once([path])

      assert_equal :fixed, result.fetch(:status)
      assert_equal 1, result.fetch(:fixed)
      assert_equal "clean\n", File.read(path)
      assert_operator scanner.paths.count(path), :>=, 2
      assert_includes bus.events.map(&:first), "repair_loop:fix_applied"
      selected = bus.events.find { |event, _| event == "repair_loop:candidate_selected_unverified" }
      refute_nil selected, "an unmapped scratch target must not claim focused-test proof"
      assert_empty selected.last.fetch(:tests)
      refute_includes bus.events.map(&:first), "repair_loop:candidate_selected"

      assert_empty scanner.scan(path).value!, "a fresh scan must find no remaining violation"
    end
  ensure
    previous_scan_agreement.nil? ? ENV.delete("MASTER_FIX_SCAN_AGREEMENT") : ENV["MASTER_FIX_SCAN_AGREEMENT"] = previous_scan_agreement
  end

  class SilentAgent
    def ask(_prompt) = ""
    def ask_once(_prompt, **) = ""
  end

  # The 2026-08-19 proof run reported fixed=0 for 33 minutes and the log could
  # not say why: every non-apply collapsed to false before the one aggregate
  # line. Each outcome is a named symbol now, and a model that returns nothing
  # is :no_proposal — a different problem from a proposal dying in review, and
  # the breakdown line must say which.
  def test_a_model_that_returns_nothing_is_a_named_outcome
    Dir.mktmpdir do |root|
      path = File.join(root, "sample.rb")
      File.write(path, "puts :x\n")
      bus = FakeBus.new
      loop = build_loop(root:, bus:, scanner: Scanner.new, agent: SilentAgent.new)

      outcome = loop.send(:fix_violation,
                          Master::Fix::Violation.from_finding(
                            { law: "TEST_RULE", severity: :warning, line: 1, message: "fix me" },
                            file: path, ext: ".rb",
                          ))

      assert_equal :no_proposal, outcome
    end
  end

  # MASTER_AUTOFIX is what a person asking looks like from inside the loop. The
  # background convergence pass and the unattended four-tree ladder both leave
  # it unset, and a transform that deletes is refused for them.
  def test_the_loop_asks_for_deletions_only_when_a_person_did
    assert_equal [true], deletions_asked_with("1")
    assert_equal [false], deletions_asked_with(nil)
  end

  # High-risk fixes require independent consensus even when no environment
  # switch is present. Lower-risk fixes remain opt-in to control spend.
  def test_error_and_critical_fixes_require_consensus_by_default
    Dir.mktmpdir do |root|
      asked = []
      consensus = Object.new
      consensus.define_singleton_method(:approve_fix?) { |**kwargs| asked << kwargs[:candidate]; false }
      agent = Agent.new
      agent.define_singleton_method(:consensus) { consensus }
      loop = build_loop(root:, bus: FakeBus.new, scanner: Scanner.new, agent:)
      previous = ENV["MASTER_CONSENSUS_FIXES"]

      ENV.delete("MASTER_CONSENSUS_FIXES")
      %i[error critical].each do |severity|
        violation = { file: File.join(root, "sample.rb"), law: "TEST_RULE", severity: }
        refute loop.send(:consensus_approves?, violation, "candidate-#{severity}")
      end
      assert_equal %w[candidate-error candidate-critical], asked
    ensure
      previous.nil? ? ENV.delete("MASTER_CONSENSUS_FIXES") : ENV["MASTER_CONSENSUS_FIXES"] = previous
    end
  end

  def test_warning_fixes_keep_consensus_opt_in
    Dir.mktmpdir do |root|
      asked = []
      consensus = Object.new
      consensus.define_singleton_method(:approve_fix?) { |**kwargs| asked << kwargs[:candidate]; false }
      agent = Agent.new
      agent.define_singleton_method(:consensus) { consensus }
      loop = build_loop(root:, bus: FakeBus.new, scanner: Scanner.new, agent:)
      violation = { file: File.join(root, "sample.rb"), law: "TEST_RULE", severity: :warning }
      previous = ENV["MASTER_CONSENSUS_FIXES"]

      ENV.delete("MASTER_CONSENSUS_FIXES")
      assert loop.send(:consensus_approves?, violation, "warning-default")
      assert_empty asked

      ENV["MASTER_CONSENSUS_FIXES"] = "1"
      refute loop.send(:consensus_approves?, violation, "warning-opt-in")
      assert_equal ["warning-opt-in"], asked
    ensure
      previous.nil? ? ENV.delete("MASTER_CONSENSUS_FIXES") : ENV["MASTER_CONSENSUS_FIXES"] = previous
    end
  end

  # reversibility and blast_radius travel from the finding to the violation, and
  # an irreversible or multi-file fix waits for a person like a deletion does.
  def test_an_irreversible_fix_produces_a_human_decision_outcome
    Dir.mktmpdir do |root|
      path = File.join(root, "sample.rb")
      File.write(path, "puts :x\n")
      bus = FakeBus.new
      loop = build_loop(root:, bus:, scanner: Scanner.new, agent: Agent.new)
      violation = Master::Fix::Violation.from_finding(
        { law: "TEST_RULE", severity: :warning, line: 1, message: "fix me", reversibility: "impossible" },
        file: path, ext: ".rb",
      )

      assert_equal :needs_person, loop.send(:fix_violation, violation)
      assert_includes bus.events.map(&:first), "repair_loop:human_decision_required"
    end
  end

  def test_an_irreversible_or_wide_fix_waits_for_a_person
    Dir.mktmpdir do |root|
      loop = build_loop(root:, bus: FakeBus.new, scanner: Scanner.new, agent: Agent.new)
      base = { law: "TEST_RULE", severity: :warning, line: 1, message: "fix me" }
      path = File.join(root, "sample.rb")
      violation = ->(extra) { Master::Fix::Violation.from_finding(base.merge(extra), file: path, ext: ".rb") }

      previous = ENV["MASTER_AUTOFIX"]
      ENV["MASTER_AUTOFIX"] = nil
      refute loop.send(:autofix_allowed?, violation.call(reversibility: "impossible"))
      refute loop.send(:autofix_allowed?, violation.call(blast_radius: { "files_touched" => 3 }))
      assert loop.send(:autofix_allowed?, violation.call(reversibility: "cheap", blast_radius: { "files_touched" => 1 }))
      ENV["MASTER_AUTOFIX"] = "1"
      assert loop.send(:autofix_allowed?, violation.call(reversibility: "impossible"))
    ensure
      ENV["MASTER_AUTOFIX"] = previous
    end
  end

  def deletions_asked_with(flag)
    Dir.mktmpdir do |root|
      path = File.join(root, "sample.rb")
      File.write(path, "puts :x\n")
      scanner = Scanner.new(allow_autofix: false)
      loop = build_loop(root:, bus: FakeBus.new, scanner:, agent: Agent.new)

      previous = ENV["MASTER_AUTOFIX"]
      ENV["MASTER_AUTOFIX"] = flag
      begin
        loop.run_once([path])
      ensure
        ENV["MASTER_AUTOFIX"] = previous
      end
      scanner.deletions_asked
    end
  end

  def build_loop(root:, bus:, scanner:, agent:)
    Master::Fix::RepairLoop.new(
      law: Rule.new("TEST_RULE", :warning),
      agent:,
      scanner:,
      root:,
      bus:,
    )
  end
end
