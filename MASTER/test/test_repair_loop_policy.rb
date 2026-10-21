# frozen_string_literal: true

require "fileutils"
require "json"
require "tmpdir"
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
  # fix_quality every time the gate fires, deprioritizing it further with no
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

class TestUserSimulation < Minitest::Test
  UserSimulation = Master::Fix::UserSimulation
  CAMPAIGN = File.join(Master::REPO_ROOT, "RAILS", "test", "interaction_campaign_400.json")

  def test_simulator_reuses_the_existing_candidate_owner_file
    owner = File.join(Master::REPO_ROOT, "MASTER", "lib", "fix", "best_of_n.rb")
    strategy = File.join(Master::REPO_ROOT, "MASTER", "lib", "fix", "repair_loop", "fix_strategies.rb")
    standalone = File.join(Master::REPO_ROOT, "MASTER", "lib", "fix", "user_simulation.rb")

    assert File.file?(owner)
    assert_includes File.read(owner), "class UserSimulation"
    assert_includes File.read(strategy), 'require_relative "../best_of_n"'
    refute File.exist?(standalone), "the simulator must not create a second implementation file"
  end

  def test_campaign_schema_and_runtime_evidence_are_validated
    campaign = JSON.parse(File.read(CAMPAIGN, encoding: "UTF-8"))

    assert_equal 400, campaign.fetch("cases").length
    assert_equal 20, campaign.fetch("surfaces").length
    assert_equal 20, campaign.fetch("fault_modes").length
    assert_equal 400, campaign.fetch("cases").map { |row| row.fetch("id") }.uniq.length

    campaign.fetch("cases").each do |row|
      assert_includes UserSimulation::RUNTIME_STATES, row.fetch("runtime_status")
      if %w[PASS FAIL].include?(row.fetch("runtime_status"))
        refute_empty row.fetch("runtime_evidence").to_s, "#{row.fetch("id")} requires runtime evidence"
      end
    end
  end

  def test_every_focused_test_mapping_points_to_a_real_test_file
    surfaces = JSON.parse(File.read(CAMPAIGN, encoding: "UTF-8")).fetch("surfaces")

    surfaces.each do |surface|
      name = surface.fetch("id")
      paths = surface.fetch("focused_test_paths")
      refute_empty paths, "#{name} has no focused test mapping"
      assert_equal paths.length, paths.uniq.length, "#{name} repeats a test path"

      paths.each do |relative|
        refute relative.start_with?("/"), "#{name}: absolute test path #{relative}"
        refute relative.split("/").include?(".."), "#{name}: test path escapes the repository"
        assert File.file?(File.join(Master::REPO_ROOT, relative)),
               "#{name}: focused test path is missing: #{relative}"
      end

      assert_equal paths, UserSimulation.new(root: Master::REPO_ROOT, campaign_path: CAMPAIGN).focused_test_paths_for(name),
                   "#{name}: runtime resolver diverged from the campaign manifest"
    end
  end

  def test_relevant_user_scenarios_are_prompted_as_oracles_not_results
    simulation = UserSimulation.new(root: Master::REPO_ROOT)
    path = File.join(Master::REPO_ROOT, "RAILS", "brgen", "app", "controllers", "posts_controller.rb")

    context = simulation.scenario_context(path:)

    assert_includes context, "USER-SIMULATION ORACLES"
    assert_includes context, "RI-021"
    assert_includes context, "not an executed test"
    assert_includes context, "inventory_state=NOT_RUN"
  end

  def test_candidate_approaches_are_materially_distinct_and_bounded
    approaches = (0...3).map { |index| UserSimulation.approach(index) }

    assert_equal 3, approaches.map { |row| row.fetch(:name) }.uniq.length
    assert_equal 3, approaches.map { |row| row.fetch(:instruction) }.uniq.length
    assert_operator UserSimulation.candidate_count, :>=, 2
    assert_operator UserSimulation.candidate_count, :<=, 5
  end

  def test_passing_candidate_is_tested_and_original_source_is_restored
    Dir.mktmpdir("master-user-simulation") do |root|
      path, tests = fixture_tree(root, "broken\n")
      runner = lambda do |_test_path|
        File.read(path).strip == "fixed" ?
          { state: :pass, signature: "pass" } :
          { state: :fail, signature: "baseline-failure" }
      end
      simulation = UserSimulation.new(root:, campaign_path: CAMPAIGN, runner:)
      writer = ->(target, text) { File.write(target, text) }

      results = simulation.evaluate_candidates(
        path:, original: "broken\n", candidates: ["fixed\n"], writer:
      )

      assert_equal :pass, results.fetch(0).fetch(:status)
      assert_equal tests.sort, results.fetch(0).fetch(:test_paths).sort
      assert_equal "broken\n", File.read(path)
    end
  end

  def test_candidate_introducing_failure_is_rejected_and_source_is_restored
    Dir.mktmpdir("master-user-simulation") do |root|
      path, = fixture_tree(root, "safe\n")
      runner = lambda do |_test_path|
        if File.read(path).strip == "safe"
          { state: :pass, signature: "pass" }
        else
          { state: :fail, signature: "new-failure" }
        end
      end
      simulation = UserSimulation.new(root:, campaign_path: CAMPAIGN, runner:)
      writer = ->(target, text) { File.write(target, text) }

      result = simulation.evaluate_candidates(
        path:, original: "safe\n", candidates: ["broken\n"], writer:
      ).fetch(0)

      assert_equal :regression, result.fetch(:status)
      refute_empty result.fetch(:regressions)
      assert_equal "safe\n", File.read(path)
    end
  end

  def test_unavailable_runner_is_blocked_not_passed
    Dir.mktmpdir("master-user-simulation") do |root|
      path, = fixture_tree(root, "safe\n")
      runner = ->(_test_path) { { state: :blocked, signature: "browser-unavailable", detail: "browser unavailable" } }
      simulation = UserSimulation.new(root:, campaign_path: CAMPAIGN, runner:)
      writer = ->(target, text) { File.write(target, text) }

      result = simulation.evaluate_candidates(
        path:, original: "safe\n", candidates: ["fixed\n"], writer:
      ).fetch(0)

      assert_equal :blocked, result.fetch(:status)
      refute_equal :pass, result.fetch(:status)
      assert_equal "safe\n", File.read(path)
    end
  end

  def test_candidate_simulation_never_overwrites_concurrent_source_changes
    Dir.mktmpdir("master-user-simulation") do |root|
      path, = fixture_tree(root, "safe\n")
      runner = lambda do |_test_path|
        File.write(path, "concurrent edit\n") if File.read(path).strip == "candidate"
        { state: :pass, signature: "pass" }
      end
      simulation = UserSimulation.new(root:, campaign_path: CAMPAIGN, runner:)
      writer = ->(target, text) { File.write(target, text) }

      error = assert_raises(UserSimulation::RestoreFailure) do
        simulation.evaluate_candidates(
          path:, original: "safe\n", candidates: ["candidate\n"], writer:
        )
      end

      assert_match(/refusing to overwrite concurrent content/, error.message)
      assert_equal "concurrent edit\n", File.read(path)
    end
  end

  def test_symlinked_target_is_blocked_without_writing_through_the_link
    Dir.mktmpdir("master-user-simulation") do |root|
      outside = File.join(root, "outside.rb")
      File.write(outside, "outside original\n")
      path = File.join(root, "RAILS", "brgen", "app", "models", "post.rb")
      FileUtils.mkdir_p(File.dirname(path))
      File.symlink(outside, path)
      write_called = false
      simulation = UserSimulation.new(root:, campaign_path: CAMPAIGN)
      writer = lambda do |target, text|
        write_called = true
        File.write(target, text)
      end

      result = simulation.evaluate_candidates(
        path:, original: "outside original\n", candidates: ["candidate\n"], writer:
      ).fetch(0)

      assert_equal :blocked, result.fetch(:status)
      refute write_called
      assert File.symlink?(path)
      assert_equal "outside original\n", File.read(outside)
    end
  end

  def test_insufficient_file_budget_blocks_before_touching_source
    Dir.mktmpdir("master-user-simulation") do |root|
      path, = fixture_tree(root, "safe\n")
      write_called = false
      simulation = UserSimulation.new(
        root:, campaign_path: CAMPAIGN,
        deadline: Process.clock_gettime(Process::CLOCK_MONOTONIC) + 1
      )
      writer = lambda do |target, text|
        write_called = true
        File.write(target, text)
      end

      result = simulation.evaluate_candidates(
        path:, original: "safe\n", candidates: ["candidate\n"], writer:
      ).fetch(0)

      assert_equal :blocked, result.fetch(:status)
      assert_match(/file budget cannot reserve/, result.fetch(:reason))
      refute write_called
      assert_equal "safe\n", File.read(path)
    end
  end

  def test_missing_test_mapping_is_explicit_and_does_not_write_a_candidate
    Dir.mktmpdir("master-user-simulation") do |root|
      path = File.join(root, "misc", "sample.rb")
      FileUtils.mkdir_p(File.dirname(path))
      File.write(path, "original\n")
      write_called = false
      simulation = UserSimulation.new(root:, campaign_path: CAMPAIGN)
      writer = lambda do |target, text|
        write_called = true
        File.write(target, text)
      end

      result = simulation.evaluate_candidates(
        path:, original: "original\n", candidates: ["candidate\n"], writer:
      ).fetch(0)

      assert_equal :unavailable, result.fetch(:status)
      refute write_called, "no candidate source should be changed when there is no focused test"
      assert_equal "original\n", File.read(path)
    end
  end

  private

  def fixture_tree(root, source)
    path = File.join(root, "RAILS", "brgen", "app", "models", "post.rb")
    tests = UserSimulation.new(root:, campaign_path: CAMPAIGN).focused_test_paths_for("brgen_social")
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, source)
    tests.each do |test_path|
      absolute = File.join(root, test_path)
      FileUtils.mkdir_p(File.dirname(absolute))
      File.write(absolute, "# isolated fake test path\n")
    end
    [path, tests]
  end
end
