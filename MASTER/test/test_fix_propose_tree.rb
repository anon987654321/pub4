# frozen_string_literal: true

require_relative "test_helper"

# ProposeTree runs when a fix loop goes clean or plateaus: it shows the agent
# a bounded recursive lib/ inventory, ranks for legibility and ownership, and
# cools down for a day. Every failure is a message, never a raise into the bus thread.
class TestFixProposeTree < Minitest::Test
  RecordingAgent = Struct.new(:reply, :prompts) do
    def ask(prompt)
      prompts << prompt
      reply
    end
  end

  REPLY = <<~YAML
    Here you go:
    - name: long
      summary: many files
      wins: a
      costs: b
      sketch: "lib/\\n  a/\\n  b/\\n  c/"
    - name: short
      summary: one file
      wins: c
      costs: d
      sketch: "lib/"
    - summary: nameless and dropped
  YAML

  def setup
    @root = Dir.mktmpdir("propose_tree_")
    FileUtils.mkdir_p(File.join(@root, "lib", "review", "scan"))
    File.write(File.join(@root, "lib", "review", "rule.rb"), "")
    File.write(File.join(@root, "lib", "master.rb"), "")
  end

  def teardown
    FileUtils.rm_rf(@root)
  end

  def test_shows_the_agent_a_bounded_recursive_inventory_and_sprawl
    FileUtils.mkdir_p(File.join(@root, "lib", "review", "scan", "deep"))
    File.write(File.join(@root, "lib", "review", "scan", "deep", "core.rb"), "x" * 500)
    agent = RecordingAgent.new(REPLY, [])
    Master::Fix::ProposeTree.new(root: @root, agent:).call(n: 2)

    prompt = agent.prompts.first
    assert_includes prompt, "lib/\n  review/\n    rule.rb\n    scan/\n      deep/\n        core.rb"
    assert_match(/files=\d+ dirs=\d+ sprawl=/, prompt)
  end

  def test_keeps_named_proposals_ranked_by_tree_quality_and_writes_the_report
    message = Master::Fix::ProposeTree.new(root: @root, agent: RecordingAgent.new(REPLY, [])).call(n: 2)

    assert_equal "propose-tree: drafted 2, kept top 2 -> runtime/proposals.md", message
    report = File.read(File.join(@root, "runtime", "proposals.md"))
    assert_operator report.index("1. short"), :<, report.index("2. long")
  end

  def test_ranking_prefers_a_clean_owned_tree_over_a_smaller_ugly_sketch
    agent = RecordingAgent.new(REPLY, [])
    subject = Master::Fix::ProposeTree.new(root: @root, agent:)
    compact_but_ugly = {
      "name" => "compact",
      "sketch" => "lib/\n        __old/\n          deep/\n            core.rb"
    }
    clear_and_shallow = {
      "name" => "clear",
      "sketch" => "lib/\n  runtime/\n  mind/\n  design/\n  operator/"
    }

    ranked = subject.send(:rank, [compact_but_ugly, clear_and_shallow])

    assert_equal %w[clear compact], ranked.map { |proposal| proposal.fetch("name") }
  end

  def test_ranking_penalizes_the_same_concept_scattered_across_three_owners
    agent = RecordingAgent.new(REPLY, [])
    subject = Master::Fix::ProposeTree.new(root: @root, agent:)
    scattered = <<~TREE
      lib/
        runtime/
          dispatch_policy.rb
        mind/
          dispatch_policy.rb
        design/
          dispatch_policy.rb
    TREE
    owned = <<~TREE
      lib/
        runtime/
          dispatch_policy.rb
    TREE

    assert_operator subject.send(:sketch_score, scattered)[1], :>,
                    subject.send(:sketch_score, owned)[1]
  end

  def test_current_tree_measures_root_clutter_at_the_lib_boundary
    19.times do |index|
      File.write(File.join(@root, "lib", "root_#{index}.rb"), "x" * 240)
    end

    summary = Master::Fix::ProposeTree.new(root: @root, agent: RecordingAgent.new(REPLY, []))
                                      .send(:current_tree)

    assert_match(/"root_clutter":19/, summary)
  end

  def test_root_clutter_counts_root_files_not_top_level_directories
    agent = RecordingAgent.new(REPLY, [])
    subject = Master::Fix::ProposeTree.new(root: @root, agent:)
    directories = ["lib/"] + 19.times.map { |index| "  group_#{index}/" }
    files = ["lib/"] + 19.times.map { |index| "  root_#{index}.rb" }

    assert_equal 0, subject.send(:sketch_score, directories.join("\n"))[4]
    assert_equal 1, subject.send(:sketch_score, files.join("\n"))[4]
  end

  def test_a_recent_report_cools_the_proposal_down
    FileUtils.mkdir_p(File.join(@root, "runtime"))
    File.write(File.join(@root, "runtime", "proposals.md"), "previous")
    agent = RecordingAgent.new(REPLY, [])

    assert_match(/cooldown/, Master::Fix::ProposeTree.new(root: @root, agent:).call)
    assert_empty agent.prompts
  end

  def test_an_unparseable_reply_is_reported_rather_than_raised
    message = Master::Fix::ProposeTree.new(root: @root, agent: RecordingAgent.new("no yaml here", [])).call

    assert_equal "propose-tree: parse failed", message
  end
end
