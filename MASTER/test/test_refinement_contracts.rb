# frozen_string_literal: true

require_relative "test_helper"
require "yaml"
require_relative "../lib/design/typography"
require_relative "../lib/cli/presentation_contract"
require_relative "../lib/cli/operator_grammar"
require_relative "../lib/cli/context_layers"
require_relative "../lib/operator/capability_graph"
require_relative "../lib/operator/constitution_contract"
require_relative "../lib/operator/sprawl_census"

class TestRefinementContracts < Minitest::Test
  FIXTURE = File.expand_path("fixtures/operator_contract.yml", __dir__)

  def fixture
    YAML.safe_load_file(FIXTURE)
  end

  def test_bringhurst_contract_is_measurable
    contract = Master::Design::Typography.bringhurst
    assert_equal "The Elements of Typographic Style", contract[:authority]
    assert_equal 66, contract[:measure]
    assert_equal false, contract[:body_letter_spacing]
    assert_equal [0.05, 0.15], contract[:all_caps_tracking_em]
  end

  def test_golden_operator_grammar
    fixture.fetch("cases").each do |row|
      parsed = Master::CLI::OperatorGrammar.parse(row.fetch("input"))
      expected = row["grammar"]
      assert_equal expected&.to_sym, parsed&.kind, row["id"]
    end
  end

  def test_context_layers_keep_machine_state_out_of_model_context
    refute Master::CLI::ContextLayers.model_visible?(:telemetry)
    refute Master::CLI::ContextLayers.model_visible?(:state)
    assert Master::CLI::ContextLayers.model_visible?(:conversation)
    assert Master::CLI::ContextLayers.model_visible?(:task)
  end

  def test_status_contract_humanises_internal_events
    lines = Master::CLI::PresentationContract.status_lines(
      ahead_behind: [0, 0], branch: "main", head: "abc", dirty: false,
      svc: { state: "ok" }, bg: "stopped", af: "off", stage: nil, verdict: "",
      bndl: nil, failures: ["retry_attempt3: timeout"], rsi: [], config: {},
    )
    assert_includes lines, "recent failure: retry attempt: timeout"
    refute lines.any? { |line| line.start_with?("trace0:") }
  end

  def test_capability_graph_persists_a_state_record
    root = Dir.mktmpdir("master-capabilities")
    graph = Operator::CapabilityGraph.new(root:)
    payload = graph.refresh
    assert File.file?(File.join(root, ".master", "capabilities.json"))
    assert payload.fetch("nodes").key?("constitution")
  end

  def test_base_tree_contracts_are_present
    assert_empty Operator::SprawlCensus.base_tree_findings
  end

  def test_constitution_contract_is_clean
    result = Operator::ConstitutionContract.new.check
    assert result.clean?
    assert_empty result.issues
  end
end
