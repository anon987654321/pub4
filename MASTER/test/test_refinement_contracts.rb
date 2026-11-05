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
    lines = Master::CLI::PresentationContract.status_lines({
      ahead_behind: [0, 0], branch: "main", head: "abc", dirty: false,
      svc: { state: "ok" }, bg: "stopped", af: "off", stage: nil, verdict: "",
      bndl: nil, failures: ["retry_attempt3: timeout"], rsi: [], config: {} },
    )
    assert_includes lines, "recent failure: retry attempt: timeout"
    refute lines.any? { |line| line.start_with?("trace0:") }
  end

  def test_status_keeps_opportunities_and_history_in_verbose_mode
    data = {
      ahead_behind: [0, 0], branch: "main", head: "abc", dirty: false,
      svc: { state: "ok" }, bg: "stopped", af: "off", stage: nil, verdict: "",
      bndl: nil, failures: ["cli:bg_error 2m ago: first", "error:swallowed 1m ago: second"],
      rsi: [{ dimension: "ask_llm", fail_rate: 1.0, total: 36 }], config: {}
    }

    normal = Master::CLI::PresentationContract.status_lines(data)
    verbose = Master::CLI::PresentationContract.status_lines(data, verbose: true)

    assert_equal 1, normal.count { |line| line.start_with?("recent failure:") }
    refute normal.any? { |line| line.start_with?("opportunity:") }
    assert_equal 2, verbose.count { |line| line.start_with?("recent failure:") }
    assert_includes verbose, "opportunity: ask llm failed 100% of 36 calls"
  end

  def test_capability_graph_does_not_call_an_unobserved_model_healthy
    Dir.mktmpdir("master-capabilities") do |root|
      payload = Operator::CapabilityGraph.new(root:).refresh(model: "ollama:test")
      assert_equal "unknown", payload.dig("nodes", "model")
    end
  end

  def test_capability_graph_persists_a_state_record
    Dir.mktmpdir("master-capabilities") do |root|
      payload = Operator::CapabilityGraph.new(root:).refresh
      assert File.file?(File.join(root, ".master", "capabilities.json"))
      assert payload.fetch("nodes").key?("constitution")
    end
  end

  def test_base_tree_contracts_are_present
    assert_empty Operator::SprawlCensus.base_tree_findings
  end

  def test_sprawl_census_counts_every_tracked_file_and_derived_directory
    census = Operator::SprawlCensus
    files = census.all_tracked
    expected_directories = files.flat_map do |path|
      parts = path.split("/")
      (1...parts.length).map { |depth| parts.first(depth).join("/") }
    end.uniq

    assert_equal files.size, census.counts.fetch("tracked_files")
    assert_equal expected_directories.size, census.counts.fetch("tracked_directories")
    assert_equal census.ceilings.fetch("tracked_files"), census.counts.fetch("tracked_files")
    assert_equal census.ceilings.fetch("tracked_directories"), census.counts.fetch("tracked_directories")
    assert_operator census.counts.fetch("tracked_files"), :>, 0
  end

  def test_growth_only_sprawl_gate_rejects_net_file_or_directory_growth
    census = Operator::SprawlCensus
    ceilings = census.ceilings
    counts = census.counts.merge("tracked_files" => ceilings.fetch("tracked_files") + 1)
    output = nil
    result = nil

    census.stub(:counts, counts) do
      output, = capture_io { result = census.run(growth_only: true) }
    end

    assert_equal 1, result
    assert_includes output, "tracked_files grew"
    assert_includes output, "tracked_directories"
  end

  def test_growth_only_sprawl_gate_allows_flat_or_reduced_structure
    census = Operator::SprawlCensus
    ceilings = census.ceilings
    counts = census.counts.merge(
      "tracked_files" => ceilings.fetch("tracked_files"),
      "tracked_directories" => ceilings.fetch("tracked_directories") - 1,
    )
    result = nil

    census.stub(:counts, counts) do
      capture_io { result = census.run(growth_only: true) }
    end

    assert_equal 0, result
  end

  def test_sprawl_ratchet_does_not_hide_an_overage_when_another_metric_falls
    census = Operator::SprawlCensus
    ceilings = census.ceilings.merge("lone_dirs" => 20, "stutter" => 0, "vague_names" => 0)
    values = ceilings.slice("lone_dirs", "stutter", "vague_names", "tracked_files", "tracked_directories")
                     .merge("lone_dirs" => 19, "tracked_files" => ceilings.fetch("tracked_files") + 1)
    writes = []
    result = nil

    census.stub(:counts, values) do
      census.stub(:ceilings, ceilings) do
        census.stub(:base_tree_findings, []) do
          File.stub(:write, ->(*args) { writes << args }) do
            capture_io { result = census.run(ratchet: true) }
          end
        end
      end
    end

    assert_equal 1, result
    assert_empty writes, "a lower metric must not ratchet away an overage in another metric"
  end

  def test_constitution_contract_is_clean
    result = Operator::ConstitutionContract.new.check
    assert result.clean?
    assert_empty result.issues
  end

  def test_constitution_contract_has_a_real_law_catalogue_gate
    source = File.read(File.expand_path("../lib/operator/constitution_contract.rb", __dir__))

    assert_includes source, "law_catalogue_issues"
    assert_includes source, "report.assert_catalogue_integrity!"
  end
end
