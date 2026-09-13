# frozen_string_literal: true

require_relative "test_helper"

# `/crew` runs six deterministic lenses over a target in parallel and asks the
# model once to consolidate them. Each lens is a pattern table; the crew must
# collect every lens exactly once and still answer when the model does not.
class TestReviewCrew < Minitest::Test
  Crew = Master::Review::ReviewCrew

  Agent = Struct.new(:prompts, :fail) do
    def ask_once(prompt)
      raise "provider down" if fail

      prompts << prompt
      "summary #{prompts.size}"
    end
  end

  Graph = Struct.new(:edges) do
    def build = { edges: }
  end

  def setup
    @root = Dir.mktmpdir("crew_")
    FileUtils.mkdir_p(File.join(@root, "app", "auth"))
    File.write(File.join(@root, "app", "auth", "login.rb"), "def go(a)\n  a  \nend\n")
    File.write(File.join(@root, "plain.rb"), "x = 1\n")
  end

  def teardown
    FileUtils.rm_rf(@root)
  end

  def findings_for(agent, code)
    agent.analyze(code, "f.rb").map { |finding| [finding.category, finding.message, finding.line] }
  end

  def test_security_and_style_lenses_name_the_line
    assert_includes findings_for(Crew::SecurityAgent.new, "x = 1\neval(input)\n"), [:security, "eval() detected", 2]
    assert_includes findings_for(Crew::StyleAgent.new, "ok\nbad   \n"), [:style, "trailing whitespace", 2]
    assert_empty findings_for(Crew::StyleAgent.new, "clean\n")
  end

  def test_performance_flags_long_lines_and_long_files
    code = "#{'x' * 121}\n" + ("y\n" * 300)

    assert_equal [[:performance, "file is 301 lines", 1], [:performance, "line 121 chars", 1]],
                 findings_for(Crew::PerformanceAgent.new, code)
  end

  def test_minimalist_flags_commented_code_unused_params_and_single_call_wrappers
    code = "# def old\ndef run(used, unused)\n  helper(used)\nend\ndef helper(v) = v\n"
    messages = findings_for(Crew::MinimalistAgent.new, code).map { |row| row[1] }

    assert_includes messages, "commented-out code"
    assert_includes messages, "parameter 'unused' appears unused in its own method body"
    assert_includes messages, "'helper' has exactly one call site"
  end

  def test_chaos_flags_an_unguarded_http_call_and_an_unbounded_retry
    messages = findings_for(Crew::ChaosAgent.new, "Net::HTTP.get(uri)\nretry\n").map { |row| row[1] }

    assert_includes messages, "external call with no rescue anywhere in the file"
    assert_includes messages, "HTTP client usage with no visible timeout"
    assert_includes messages, "retry with no visible attempt counter"
    assert_empty findings_for(Crew::ChaosAgent.new, "begin\nNet::HTTP.get(u, read_timeout: 1)\nrescue\nend\n")
  end

  def test_architecture_reports_a_require_cycle_once
    graph = Graph.new([{ type: :require, from: "a", to: "b" }, { type: :require, from: "b", to: "a" }])
    agent = Crew::ArchitectureAgent.new(root: @root, reference_graph: graph)
    agent.analyze("x\n", "one.rb")
    agent.analyze("x\n", "two.rb")

    assert_equal ["cyclic dependency detected: a -> b -> a"], agent.findings.map(&:message)
  end

  def test_the_crew_collects_every_lens_and_audits_an_auth_path
    agent = Agent.new([], false)
    result = Crew.new(agent:, root: @root).run(target: "app")

    assert_equal %w[ArchitectureAgent ChaosAgent MinimalistAgent PerformanceAgent SecurityAgent StyleAgent],
                 result.value![:agents].map { |entry| entry[:agent] }.sort
    assert_equal "summary 1\n\nsummary 2", result.value![:summary]
    assert_match(/OWASP/, agent.prompts.last, "a file under auth/ triggers the security audit")
  end

  def test_a_quiet_file_outside_a_sensitive_path_gets_no_audit
    agent = Agent.new([], false)
    Crew.new(agent:, root: @root).run(target: "plain.rb")

    assert_equal 1, agent.prompts.size
  end

  def test_without_the_model_the_crew_still_summarises_locally
    result = Crew.new(agent: Agent.new([], true), root: @root).run(target: "app/auth/login.rb")

    assert_match(/\Areview_crew: app\/auth\/login.rb — \d+ finding\(s\)/, result.value![:summary])
  end

  def test_an_empty_target_is_an_error
    assert Crew.new(agent: Agent.new([], false), root: @root).run(target: "nothing_here").err?
  end
end
