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

  def test_structural_delivery_paths_share_fix_safety_and_delivery_contracts
    restructure = File.read(File.join(Master::ROOT, "lib/fix/restructure.rb"), encoding: "UTF-8")
    rename = File.read(File.join(Master::ROOT, "lib/fix/file_rename.rb"), encoding: "UTF-8")

    assert_includes restructure, "Operator::RatchetSponsor.validate!"
    assert_includes restructure, "Ground::PreserveUserIntent"
    assert_includes restructure, "@ground_truth"
    assert_includes restructure, "@git.push"
    assert_includes restructure, "@known_good.promote!"

    assert_includes rename, "Operator::RatchetSponsor.validate!"
    assert_includes rename, "Ground::PreserveUserIntent"
    assert_includes rename, "@ground_truth"
    assert_includes rename, "@git.push"
    assert_includes rename, "@known_good.promote!"
  end

  def test_fix_committer_finds_the_nearest_bundle_for_each_rails_app
    Dir.mktmpdir("fix-committer") do |root|
      FileUtils.mkdir_p(File.join(root, "MASTER"))
      FileUtils.mkdir_p(File.join(root, "RAILS", "brgen", "app", "models"))
      FileUtils.mkdir_p(File.join(root, "RAILS", "amber", "app", "models"))
      File.write(File.join(root, "MASTER", "Gemfile"), "source \"https://rubygems.org\"\n")
      File.write(File.join(root, "RAILS", "brgen", "Gemfile"), "source \"https://rubygems.org\"\n")
      File.write(File.join(root, "RAILS", "amber", "Gemfile"), "source \"https://rubygems.org\"\n")

      committer = Master::Fix::FixLoop::Committer.new(root:)
      assert_equal File.join(root, "RAILS", "brgen"),
                   committer.send(:gemfile_root, File.join(root, "RAILS", "brgen", "app", "models", "post.rb"))
      assert_equal File.join(root, "RAILS", "amber"),
                   committer.send(:gemfile_root, File.join(root, "RAILS", "amber", "app", "models", "item.rb"))
      assert_nil committer.send(:gemfile_root, File.join(root, "OPENBSD", "bin", "check.rb"))
    end
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
