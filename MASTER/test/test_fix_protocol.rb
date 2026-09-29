# frozen_string_literal: true

require "json"
require "minitest/autorun"
require "tmpdir"
require_relative "../lib/master"
require_relative "../lib/fix/protocol"

class TestFixProtocol < Minitest::Test
  def test_instruction_distinguishes_fix_from_dry_run
    text = Master::Fix::Protocol.instruction

    assert_includes text, "/fix and --dry-run are distinct"
    assert_includes text, "Semantic ask rules are executable"
    assert_includes text, "No deterministic fixer exists"
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

      assert_equal 2, payload.fetch("fix_protocol_version")
      assert_includes payload.fetch("stages"), "semantic"
      assert_includes payload.fetch("terminal_states"), "PLATEAU"
      assert_equal 1, payload.dig("corpus", "total_regular_files")
    end
  end
end
