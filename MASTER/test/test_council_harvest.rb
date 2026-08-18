# frozen_string_literal: true

require "tmpdir"
require_relative "test_helper"
require "master"

# The directive this pins (operator, 2026-08-18): a critique is harvested
# automatically into a durable artifact, and the deliberation makes multiple
# proposals per issue, adversarially challenged, before the cherry-pick.
# Four tree-wide critiques ran that day and the one complete deliberation
# survived only as scratchpad scrollback.
class TestCouncilHarvest < Minitest::Test
  FEEDBACK = [
    { persona: "Skeptic", feedback: "apps.yml notes have grown into changelog prose\nmore detail" },
    { persona: "Judge", feedback: "strip dated clauses; git owns history" },
  ].freeze

  def test_harvest_writes_a_durable_artifact_with_all_four_layers
    Dir.mktmpdir do |root|
      path = Master::Review::Council::Harvest.write(
        mode: :general,
        files: ["RAILS/apps.yml"],
        feedback: FEEDBACK,
        ideas: { ideas: ["move notes to git", "add a notes linter"],
                 critiques: ["VERDICT: reject — a linter adds a reader nothing needs"],
                 final: "move notes to git" },
        cherry: ["move notes to git"],
        root: root,
      )

      assert File.file?(path), "no harvest written"
      body = File.read(path)
      assert_includes body, "Skeptic"
      assert_includes body, "move notes to git"
      assert_includes body, "adversarial challenges"
      assert_includes body, "cherry-picked"
      latest = File.join(root, ".master", "critiques", "general_latest.md")
      assert File.file?(latest), "no _latest pointer"
      assert_equal body, File.read(latest)
    end
  end

  def test_ideation_prompt_carries_the_panel_issues
    critic = Master::Review::Council::Critique.new(mode: :general, agent: nil, files: [])
    prompt = critic.send(:ideation_prompt, FEEDBACK)

    assert_includes prompt, "apps.yml notes have grown into changelog prose"
    assert_includes prompt, "at least two distinct"
    refute_includes prompt, "more detail", "took the whole feedback body instead of the issue line"
  end

  def test_ideation_prompt_without_feedback_keeps_the_mode_prompt
    critic = Master::Review::Council::Critique.new(mode: :general, agent: nil, files: [])
    assert_equal critic.instance_variable_get(:@mode)[:ideation_prompt], critic.send(:ideation_prompt, [])
  end

  def test_adversarial_challenge_demands_a_verdict_per_idea
    source = File.read(File.join(Master::ROOT, "lib", "review", "council", "ideation.rb"))
    challenge = source[/def critique\(ideas\).*?end\n/m]

    assert_includes challenge, "Attack each idea"
    assert_includes challenge, "VERDICT: keep"
    assert_includes challenge, "VERDICT: reject"
  end
end
