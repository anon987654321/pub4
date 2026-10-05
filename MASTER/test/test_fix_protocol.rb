# frozen_string_literal: true

require "json"
require "minitest/autorun"
require "tmpdir"
require "fileutils"
require_relative "../lib/master"
require_relative "../lib/fix/protocol"

class TestFixProtocol < Minitest::Test
  def test_instruction_distinguishes_fix_from_dry_run
    text = Master::Fix::Protocol.instruction

    assert_includes text, "/fix and --dry-run are distinct"
    assert_includes text, "Semantic ask rules are executable"
    assert_includes text, "No deterministic fixer exists"
  end

  def test_external_context_carries_the_cross_tree_operating_model
    Dir.mktmpdir("fix-context") do |root|
      FileUtils.mkdir_p(File.join(root, "RAILS"))
      FileUtils.mkdir_p(File.join(root, "OPENBSD", "data"))
      File.write(File.join(root, "RAILS", "CLAUDE.md"), "rails contract\n")
      File.write(File.join(root, "RAILS", "apps.yml"), "apps:\n  brgen:\n    domain: brgen.no\n    port: 38182\n")
      File.write(File.join(root, "OPENBSD", "RUNBOOK.md"), "runbook\n")
      File.write(File.join(root, "OPENBSD", "data", "operator.yml"), "meta:\n  source: runtime authority\n")
      File.write(
        File.join(root, "OPENBSD", "deploy_inventory.json"),
        '{"apps":[{"name":"brgen","domain":"brgen.no","port":38182}],"master_face":{"domain":"ai.brgen.no","port":53187}}'
      )

      context = Master::Fix::Protocol.context(root:, target: File.join(root, "OPENBSD"))

      assert_includes context, "OPERATING MODEL"
      assert_includes context, "feature_truth=RAILS/apps.yml"
      assert_includes context, "deploy_identity=OPENBSD/deploy_inventory.json"
      assert_includes context, "evidence_ladder: source authority → executable proof → live evidence"
      assert_includes context, "cross-tree proof rule: identify the authority"
      assert_includes context, '"target": "OPENBSD"'
    end
  end

  def test_render_uses_the_canonical_law_contract_digest
    Dir.mktmpdir("fix-protocol-digest") do |root|
      File.write(File.join(root, "thing.rb"), "puts :ok\n")

      payload = JSON.parse(Master::Fix::Protocol.render(root:, target: root))

      assert_equal Law::Contract.digest, payload.fetch("law_digest")
    end
  end

  def test_rule_metadata_exposes_machine_readable_repair_and_verification
    law = Master::Fix::Protocol.rules.find(&:semantic?)

    refute_nil law
    entry = Master::Fix::Protocol.rule_entry(law)

    assert entry.key?("fix_strategy")
    assert entry.key?("verify_strategy")
    assert entry.key?("enforcement")
    assert_equal "semantic_model_repair", entry.fetch("fix_strategy")
  end

  def test_render_has_live_corpus_and_terminal_states
    Dir.mktmpdir("fix-protocol") do |root|
      File.write(File.join(root, "thing.rb"), "puts :ok\n")

      payload = JSON.parse(Master::Fix::Protocol.render(root:, target: root))

      assert_equal Master::Fix::Protocol::VERSION, payload.fetch("fix_protocol_version")
      assert_includes payload.fetch("stages"), "semantic"
      assert_includes payload.fetch("terminal_states"), "PLATEAU"
      assert_equal 1, payload.dig("corpus", "total_regular_files")
      assert_kind_of Hash, payload.fetch("detector_matrix")
      assert_kind_of Hash, payload.fetch("detector_summary")
      assert_equal payload.fetch("detector_matrix").size,
                   payload.dig("detector_summary", "total_rules")
    end
  end
end
