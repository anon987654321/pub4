# frozen_string_literal: true

require_relative "test_helper"
require "tmpdir"

class TestFixReflection < Minitest::Test
  class Agent
    attr_reader :prompts

    def initialize(reply)
      @reply = reply
      @prompts = []
    end

    def ask(prompt, operation:)
      raise "wrong operation" unless operation == :reflection
      @prompts << prompt
      @reply
    end
  end

  def setup
    @root = Dir.mktmpdir("fix_reflection")
    FileUtils.mkdir_p(File.join(@root, "lib"))
    File.write(File.join(@root, "lib", "example.rb"), "puts :example\n")
  end

  def teardown
    FileUtils.remove_entry(@root) if @root && Dir.exist?(@root)
  end

  def test_keep_is_read_only
    agent = Agent.new(<<~TEXT)
      VERDICT: KEEP
      SUMMARY: The measured tree is coherent.
      LAW: NONE
      ANCHOR: NONE
      EVIDENCE: The run reached a verified clean state.
      NEXT: NONE
    TEXT
    reflection = Master::Fix::Reflection.new(agent:, root: @root)

    result = reflection.call(target: @root, state: "done", files: [File.join(@root, "lib/example.rb")], history: [])

    assert_equal "KEEP", result.verdict
    assert_nil result.anchor
    assert_equal "puts :example\n", File.read(File.join(@root, "lib/example.rb"))
  end

  def test_repair_requires_a_real_anchor_and_evidence
    agent = Agent.new(<<~TEXT)
      VERDICT: REPAIR
      SUMMARY: One concrete issue remains.
      LAW: SINGULARITY
      ANCHOR: lib/example.rb:1
      EVIDENCE: The supplied orientation identifies the file as the remaining duplicate source.
      NEXT: Consolidate the duplicate source and rerun the same proof.
    TEXT
    reflection = Master::Fix::Reflection.new(agent:, root: @root)

    result = reflection.call(target: @root, state: "plateau", files: [File.join(@root, "lib/example.rb")], history: [])

    assert_equal "REPAIR", result.verdict
    assert_equal "lib/example.rb:1", result.anchor
    assert_equal "SINGULARITY", result.law
    refute_empty agent.prompts
    assert_includes agent.prompts.first, "Fresh-eyes reflection"
  end

  def test_repair_with_missing_anchor_becomes_investigate
    agent = Agent.new(<<~TEXT)
      VERDICT: REPAIR
      SUMMARY: Unsupported claim.
      LAW: SINGULARITY
      ANCHOR: nowhere.rb:9
      EVIDENCE: none
      NEXT: edit it
    TEXT

    result = Master::Fix::Reflection.new(agent:, root: @root).call(
      target: @root, state: "plateau", files: [], history: []
    )

    assert_equal "INVESTIGATE", result.verdict
    assert_nil result.anchor
  end
end
