# frozen_string_literal: true

require_relative "test_helper"
require "fileutils"
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
    File.write(File.join(@root, "lib", "example.rb"), "puts :example
")
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
    result = Master::Fix::Reflection.new(agent:, root: @root).call(
      target: @root, state: "done", files: [File.join(@root, "lib/example.rb")], history: []
    )
    assert_equal "KEEP", result.verdict
    assert_equal "puts :example
", File.read(File.join(@root, "lib/example.rb"))
  end

  def test_repair_requires_a_real_law_and_anchor
    agent = Agent.new(<<~TEXT)
      VERDICT: REPAIR
      SUMMARY: A concrete issue remains.
      LAW: SINGULARITY
      ANCHOR: lib/example.rb:1
      EVIDENCE: The supplied source anchor is the measured evidence.
      NEXT: Consolidate the duplicate owner and rerun the same proof.
    TEXT
    # A temporary root has no MASTER/law registry, so the model claim is not
    # actionable; the result must become INVESTIGATE instead of inventing authority.
    result = Master::Fix::Reflection.new(agent:, root: @root).call(
      target: @root, state: "plateau", files: [], history: []
    )
    assert_equal "INVESTIGATE", result.verdict
    assert_equal "lib/example.rb:1", result.anchor
  end

  def test_invalid_anchor_downgrades_repair
    agent = Agent.new(<<~TEXT)
      VERDICT: REPAIR
      SUMMARY: Unsupported claim.
      LAW: SINGULARITY
      ANCHOR: nowhere.rb:9
      EVIDENCE: no measured source.
      NEXT: edit it
    TEXT
    result = Master::Fix::Reflection.new(agent:, root: @root).call(
      target: @root, state: "plateau", files: [], history: []
    )
    assert_equal "INVESTIGATE", result.verdict
    assert_nil result.anchor
  end
end
