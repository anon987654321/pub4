# frozen_string_literal: true

require_relative "test_helper"
require "yaml"
# Law loads lazily inside VisualUsability; tests that read it directly cannot rely on run order.
require File.join(Master::ROOT, "law", "definition")
Law.load_all(File.join(Master::ROOT, "law")) if Law.definitions.empty?

class TestVisualConstitution < Minitest::Test
  IDS = %w[
    VISUAL_HIERARCHY
    CONTEXTUAL_STATUS_CUES
    OPENBSD_DMESG_CONSOLE_STYLE
    CLI_PROMPT_COMPOSITION
    MASTER_PROMPT_AESTHETIC
  ].freeze

  def test_hierarchy_status_and_console_laws_reach_visual_review
    context = Master::Fix::VisualUsability.context

    IDS.each do |id|
      law = Law.definitions.fetch(id.to_sym) { flunk "#{id} is not registered" }
      refute_empty law.fix.to_s, "#{id} needs an actionable repair"
      assert_includes Master::Fix::VisualUsability.ids, id
      assert_includes context, id
    end
  end

  def test_cli_prompt_law_makes_openbsd_dmesg_primary
    law = Law.definitions.fetch(:CLI_PROMPT_COMPOSITION)

    assert_includes law.source, "OpenBSD dmesg"
    assert_includes law.ask, "no Starship/powerline-style segments"
    assert_includes law.fix, "plain Git state"
    refute_includes law.source.downcase, "starship bounded prompt"
  end

  def test_console_law_requires_factual_text_lines
    law = Law.definitions.fetch(:OPENBSD_DMESG_CONSOLE_STYLE)

    assert_includes law.source, "xsa/openbsd-dmesgs"
    assert_includes law.fix, "one concise factual line per event"
    assert_includes law.fix, "Do not create a second event logging format"
  end

  def test_visual_rubric_places_console_style_above_prompt_trends
    path = File.expand_path("../data/visual_rubric.yml", __dir__)
    rubric = YAML.safe_load_file(path)

    assert_includes rubric.fetch("dimensions").fetch("console"), "OpenBSD dmesg"
    assert_includes rubric.fetch("judgment").fetch("console_first"), "primary visual reference"
    assert_includes rubric.fetch("constraints").fetch("terminal"), "Master::Trace::Dmesg"
  end
end
