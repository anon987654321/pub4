# frozen_string_literal: true

require_relative "test_helper"

# data/rules.yml's markdown_style section had no reader. Its applies_to names
# MASTER, claude, grok and codex — every agent that writes markdown here — and
# nothing in the tree named the key, so the aesthetic it declares reached no
# prompt and each agent invented its own house style. data_reach had counted it
# unread since it was restored after the 2026-08 read-modify-write that reverted
# it, and 48-against-46 was the only trace.
#
# Same defect the builder's own add_attention comment records about
# attention_context.yml: a section that specified its audience and was never
# consulted. So the test that matters is not "the words appear" but "the words
# come from the file" — a restatement in the builder would satisfy the first and
# fail the second, and would be the thing the section exists to prevent.
class TestMarkdownStyleReachesThePrompt < Minitest::Test
  # A host for the module under test, so the section can be swapped without
  # constructing a Personality and its whole dependency graph.
  class Host
    include Master::Voice::PersonalityPromptBuilder

    def initialize(rules) = @rules = rules
    def sections_for(section) = {}.tap { |s| add_markdown_style(s) }.fetch(section, "")
  end

  FakeRules = Struct.new(:section) do
    def data(name) = name == :markdown_style ? section : {}
  end

  def style(rules:, aesthetic: "tadao_ando")
    { "aesthetic" => aesthetic, "applies_to" => %w[MASTER claude], "rules" => rules }
  end

  def built(section) = Host.new(FakeRules.new(section)).sections_for("master_style")

  # The load-bearing one: invented rules reach the prompt, which is only
  # possible if the file is being read.
  def test_the_rules_come_from_the_section
    out = built(style(rules: ["burn the preamble", "one idea per screen"]))

    assert_includes out, "burn the preamble"
    assert_includes out, "one idea per screen"
  end

  def test_the_aesthetic_is_named_as_prose
    assert_includes built(style(rules: ["x"], aesthetic: "tadao_ando")), "tadao ando"
  end

  def test_a_missing_aesthetic_still_produces_guidance
    out = built({ "rules" => ["cut before you add"] })

    assert_includes out, "cut before you add"
    refute_includes out, "aesthetic:"
  end

  def test_an_empty_section_adds_nothing
    assert_empty built({})
    assert_empty built({ "rules" => [] })
    assert_empty built(nil)
  end

  # The real file, not a fixture: if someone empties the section or renames the
  # key, the prompt silently loses the guidance and only this notices.
  def test_the_real_section_is_present_and_reaches_a_real_prompt
    section = Master::Ground::Rules.new.data(:markdown_style)

    assert_kind_of Hash, section, "data/rules.yml lost its markdown_style section"
    refute_empty Array(section["rules"]), "markdown_style declares no rules"

    prompt = Master::Voice::Personality.new.send(:build_system_prompt)
    Array(section["rules"]).each do |rule|
      assert_includes prompt, rule, "a declared markdown rule never reached the system prompt"
    end
  end
end
