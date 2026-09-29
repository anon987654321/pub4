# frozen_string_literal: true

require_relative "test_helper"
require "tmpdir"
require "fileutils"
require "open3"
require_relative "../lib/fix/sprawl_campaign"

class TestSprawlCampaign < Minitest::Test
  def setup
    @root = Dir.mktmpdir("sprawl_campaign")
    write("MASTER/lib/alpha.rb", "class Alpha; end\n")
    write("MASTER/lib/beta.rb", "class Beta; end\n")
    write("RAILS/shared/README.md", "shared\n")
    write("OPENBSD/bin/check", "#!/bin/sh\n")
    git("init", "-q")
    git("add", ".")
    git("-c", "user.email=t@t", "-c", "user.name=t", "commit", "-q", "-m", "seed")
  end

  def teardown = FileUtils.remove_entry(@root)

  def test_tree_targets_expand_repository_root_into_governed_trees
    campaign = Master::Fix::SprawlCampaign.new(agent: nil, repo_root: @root)
    targets = campaign.send(:tree_targets, @root)

    assert_equal %w[MASTER RAILS OPENBSD], targets.map(&:first)
    assert_equal @root + "/MASTER", targets.first.last
  end

  def test_tree_targets_accept_a_subpath_by_its_governed_tree
    campaign = Master::Fix::SprawlCampaign.new(agent: nil, repo_root: @root)
    path = File.join(@root, "RAILS", "shared")

    assert_equal [["RAILS", File.join(@root, "RAILS")]], campaign.send(:tree_targets, path)
  end

  def test_shape_score_rewards_real_structural_reduction
    campaign = Master::Fix::SprawlCampaign.new(agent: nil, repo_root: @root)
    before = {
      files: 10, directories: 4, lone_dirs: 3, stutter: 1, vague_names: 1,
      duplicate_groups: 2, deep_paths: 2,
    }
    after = before.merge(files: 9, lone_dirs: 2)

    assert_operator campaign.send(:score, before), :>, campaign.send(:score, after)
  end

  def test_campaign_prompt_forbids_cross_tree_changes_and_speculation
    agent = Object.new
    captured = nil
    agent.define_singleton_method(:ask) { |prompt, **| captured = prompt; "KEEP" }
    campaign = Master::Fix::SprawlCampaign.new(agent:, repo_root: @root)

    shape = { files: 2, directories: 1, lone_dirs: 0, stutter: 0, vague_names: 0,
              duplicate_groups: 0, deep_paths: 0, members: [] }
    prompt = campaign.send(
      :format,
      Master::Fix::SprawlCampaign::PROPOSE,
      tree: "MASTER",
      shape: campaign.send(:render_shape, shape),
      findings: "  MASTER/lib/alpha.rb — SMALL_FILES: tiny",
      contracts: "MASTER, preserve Zeitwerk",
    )

    assert_includes prompt, "no operation may cross the tree boundary"
    assert_includes prompt, "do not invent defects"
    assert_includes prompt, "MASTER/data/rules.yml"
  end
end
