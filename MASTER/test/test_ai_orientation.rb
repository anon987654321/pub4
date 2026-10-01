# frozen_string_literal: true

require_relative "test_helper"
require_relative "../lib/ai/orientation"
require "tmpdir"
require "fileutils"

class TestAiOrientation < Minitest::Test
  def setup
    @root = Dir.mktmpdir("orientation_")
    @master = File.join(@root, "MASTER")
    FileUtils.mkdir_p(File.join(@master, "lib", "io"))
    FileUtils.mkdir_p(File.join(@master, "runtime"))
    FileUtils.mkdir_p(File.join(@root, "RAILS"))
    FileUtils.mkdir_p(File.join(@root, "OPENBSD", "data"))
    File.write(File.join(@root, "CLAUDE.md"), "authority order\n")
    File.write(File.join(@root, "TREE.md"), "TREE\n")
    File.write(File.join(@root, "TODO.md"), "TODO\n")
    File.write(File.join(@master, "lib", "master.rb"), "module Master\nend\n")
    File.write(File.join(@master, "runtime", "active_plan.md"), "repair boot\nverify again\n")
    File.write(File.join(@master, "runtime", "wishlist.md"), "# MASTER wishlist\n\n### 1. Better boot receipt\n\n")
    File.write(File.join(@root, "RAILS", "CLAUDE.md"), "rails contract\n")
    File.write(File.join(@root, "RAILS", "apps.yml"), <<~YAML)
      apps:
        brgen:
          domain: brgen.no
          port: 38182
    YAML
    File.write(File.join(@root, "OPENBSD", "RUNBOOK.md"), "edge runbook\n")
    File.write(File.join(@root, "OPENBSD", "data", "operator.yml"), "meta:\n  source: runtime authority\n")
    File.write(File.join(@root, "OPENBSD", "deploy_inventory.json"), <<~JSON)
      {
        "apps": [{"name": "brgen", "domain": "brgen.no", "port": 38182}],
        "master_face": {"name": "master", "domain": "ai.brgen.no", "port": 53187}
      }
    JSON
  end

  def teardown = FileUtils.rm_rf(@root)

  def test_render_is_compact_live_context_and_includes_pending_work
    text = Master::AI::Orientation.render(root: @master, target: File.join(@master, "lib"))

    assert_includes text, "MASTER orientation v3"
    assert_includes text, "target: MASTER/lib"
    assert_includes text, "active plan: repair boot verify again"
    assert_includes text, "pending wishes: 1. Better boot receipt"
    assert_includes text, "lib/"
    assert_includes text, "io/"
    assert_includes text, "master.rb"
    refute_includes text, ".master"
  end

  def test_render_includes_cross_tree_atlas
    text = Master::AI::Orientation.render(root: @master)

    assert_equal 1, text.scan("cross-tree atlas:").size
    assert_includes text, "feature_truth=RAILS/apps.yml"
    assert_includes text, "brgen:brgen.no:38182"
    assert_includes text, "deploy_identity=OPENBSD/deploy_inventory.json"
    assert_includes text, "ai.brgen.no:53187"
    assert_includes text, "edge=pf→relayd→loopback"
    assert_includes text, "design=RAILS/shared/README.md"
    assert_includes text, "sandbox_model=MASTER/lib/ground/pledge.rb"
    assert_includes text, "lenses: authority, topology, runtime, privilege, security, design, lifecycle, resources, recovery, observability, provenance, seams"
    assert_includes text, "evidence_ladder: source authority → executable proof → live evidence"
    assert_includes text, "bridge: RAILS/apps.yml → OPENBSD/deploy_inventory.json → vps-deploy → rcctl → public health"
    assert_includes text, "inventory_alignment: clean"
    assert_includes text, "proof=RAILS/gates/gates.yml+RAILS/bin/triangle+<app>/bin/ci"
    assert_includes text, "live=target host diagnostics and public health"
  end

  def test_render_surfaces_inventory_drift
    File.write(
      File.join(@root, "OPENBSD", "deploy_inventory.json"),
      '{"apps":[{"name":"brgen","domain":"brgen.no","port":99999}],"master_face":{"domain":"ai.brgen.no","port":53187}}'
    )

    text = Master::AI::Orientation.render(root: @master)

    assert_includes text, "inventory_alignment: mismatch divergent=brgen"
  end

  def test_digest_is_stable_for_the_same_observation
    first = Master::AI::Orientation.digest(root: @master)
    second = Master::AI::Orientation.digest(root: @master)

    assert_equal first, second
    assert_match(/\A[0-9a-f]{16}\z/, first)
  end
end
