# frozen_string_literal: true

require_relative "test_helper"

# ProposeTree runs when a fix loop goes clean or plateaus: it shows the agent
# lib/, asks for radical layouts, keeps the most compact three and cools down
# for a day. Every failure is a message, never a raise into the bus thread.
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

  def test_shows_the_agent_each_directory_with_its_children
    agent = RecordingAgent.new(REPLY, [])
    Master::Fix::ProposeTree.new(root: @root, agent:).call(n: 2)

    assert_includes agent.prompts.first, "review/\n  rule.rb\n  scan/"
    assert_includes agent.prompts.first, "master.rb"
  end

  def test_keeps_named_proposals_ranked_by_sketch_size_and_writes_the_report
    message = Master::Fix::ProposeTree.new(root: @root, agent: RecordingAgent.new(REPLY, [])).call(n: 2)

    assert_equal "propose-tree: drafted 2, kept top 2 → runtime/proposals.md", message
    report = File.read(File.join(@root, "runtime", "proposals.md"))
    assert_operator report.index("1. short"), :<, report.index("2. long")
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
