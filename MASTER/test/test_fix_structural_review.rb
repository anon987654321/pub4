# frozen_string_literal: true

require_relative "test_helper"
require "tmpdir"
require "fileutils"
require "open3"

class TestFixStructuralReview < Minitest::Test
  Review = Master::Fix::StructuralReview

  class FakeAgent
    attr_reader :prompts

    def initialize(answer)
      @answer = answer
      @prompts = []
    end

    def ask(prompt, **)
      @prompts << prompt
      @answer.is_a?(Proc) ? @answer.call : @answer
    end
  end

  def setup
    @root = Dir.mktmpdir("fix-structural-review")
    %w[lib/a.rb lib/a_helper.rb lonely/only.rb].each do |path|
      FileUtils.mkdir_p(File.dirname(File.join(@root, path)))
      File.write(File.join(@root, path), "x" * 400)
    end
    Open3.capture2e("git", "-C", @root, "init", "-q")
    Open3.capture2e("git", "-C", @root, "add", ".")
  end

  def teardown = FileUtils.remove_entry(@root)

  def test_a_finding_over_known_paths_and_a_real_law_is_kept_and_saved
    agent = FakeAgent.new("FINDING: over_engineered | lib/a.rb, lib/a_helper.rb | SINGULARITY | one concept in two\n")
    result = Review.new(agent:, root: @root).call(target: @root)

    assert_predicate result, :answered?
    assert_equal "over_engineered", result.findings.first.kind
    assert_equal "SINGULARITY", result.findings.first.law
    assert_equal "over_engineered", Review.findings(@root).first["kind"]
  end

  def test_a_citation_of_a_law_that_does_not_exist_is_cleared_not_the_finding
    agent = FakeAgent.new("FINDING: odd | lonely/only.rb | NOT_A_REAL_LAW | a folder for one file\n")
    result = Review.new(agent:, root: @root).call(target: @root)

    assert_equal 1, result.findings.size
    assert_nil result.findings.first.law
  end

  def test_a_finding_naming_an_unknown_path_or_category_is_dropped
    agent = FakeAgent.new(
      "FINDING: odd | lib/missing.rb | NONE | not there\nFINDING: rewrite_everything | lib/a.rb | NONE | no\n",
    )
    result = Review.new(agent:, root: @root).call(target: @root)

    assert_empty result.findings
    assert_equal 2, result.dropped
  end

  def test_the_prompt_protects_the_core_and_carries_the_constitution
    agent = FakeAgent.new("")
    Review.new(agent:, root: @root).call(target: @root)

    prompt = agent.prompts.first.gsub(/\s+/, " ")

    assert_includes prompt, "do not recommend a rewrite of what works"
    assert_includes prompt, "Constitutional Laws:"
  end

  def test_no_model_or_a_failing_model_is_reported_and_does_not_raise
    assert_equal :unavailable, Review.new(agent: Object.new, root: @root).call(target: @root).state

    broken = FakeAgent.new(-> { raise "lane down" })

    assert_equal :inconclusive, Review.new(agent: broken, root: @root).call(target: @root).state
  end

  def test_read_only_review_uses_current_hints_without_persisting_findings
    hints = [{ kind: "merge", paths: %w[lib/a.rb lib/a_helper.rb], law: "SINGULARITY", reason: "one concept" }]
    agent = FakeAgent.new("FINDING: odd | lonely/only.rb | NONE | unusual shape\n")

    result = Review.new(agent:, root: @root).call(
      target: @root, persist: false, first_read_proposals: hints,
    )

    assert_predicate result, :answered?
    assert_equal 1, result.findings.size
    assert_includes agent.prompts.first, JSON.generate(hints)
    refute File.exist?(Review.findings_path(@root)), "read-only structural review must not save findings"
    refute Dir.exist?(File.join(@root, ".master")), "read-only structural review must not create state directories"
  end
end
