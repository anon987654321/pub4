# frozen_string_literal: true

require "minitest/autorun"
require_relative "../../lib/master"

# MASTER kept introducing itself, and two things caused it.
#
# Measured against the live face on 2026-08-14: told "my name is Johann,
# remember it", it answered "hi Johann it's great to meet you I'm MASTER and
# I'm the world's first AI built entirely in pure Ruby no Python no external ML
# frameworks just Ruby all the way down..." and kept going. Memory was never the
# problem — the next turn recalled the name correctly. It was the prompt.
#
# 1. Nothing forbade it. <master_output_format> banned "Certainly" and "Of
#    course" and said nothing about a self-description.
# 2. <master_identity> was fed IDENTITY.md whole, including the file's own
#    documentation: a heading, then two paragraphs explaining what an identity
#    file holds and that constitutional identity comes from soul.yml. The model
#    was handed documentation about a config file as its sense of self, in the
#    one block of the prompt that answers "who are you", and behaved like it.
#
# Both halves are asserted here because either alone regresses quietly: a rule
# nobody reads, or a loader that starts pasting the manual back in.
class IdentitySpec < Minitest::Test
  def personality = @personality ||= Master::Voice::Personality.new

  def system_prompt = @system_prompt ||= personality.system_prompt

  def identity_block = system_prompt[%r{<master_identity>.*?</master_identity>}m].to_s

  def test_the_prompt_forbids_introducing_itself
    assert_match(/Never introduce or describe yourself/, system_prompt,
                 "the output contract no longer forbids a self-introduction")
  end

  # The specific nouns it reached for. A rule that says "be concise" would not
  # have stopped this reply; naming the material is what does.
  def test_the_rule_names_what_it_reached_for
    rule = system_prompt[/Never introduce or describe yourself[^\n]*/].to_s

    %w[Ruby constitution voice].each do |subject|
      assert_includes rule, subject, "the rule should name #{subject} — it is what the reply talked about"
    end
  end

  # The identity block is who it is, not a description of the file that holds
  # who it is.
  def test_the_identity_block_carries_no_documentation_about_itself
    refute_match(/^#\s/, identity_block, "a markdown heading reached the identity block")
    refute_includes identity_block, "IDENTITY holds",
                    "IDENTITY.md's own explanation of itself is being handed to the model as its identity"
    refute_includes identity_block, "soul.yml",
                    "the identity block should not tell the model where its constitution is filed"
  end

  # Both directions, so the loader cannot be fixed into uselessness: the
  # documentation must be dropped AND the operator's actual notes must survive.
  def test_identity_notes_drops_the_manual_and_keeps_the_notes
    raw = <<~MARKDOWN
      <!--
      # IDENTITY
      Documentation for the human. IDENTITY holds the active persona.
      -->

      # A heading that is also not identity

      Speak plainly. Do not pad.
    MARKDOWN

    notes = personality.send(:identity_notes, raw)

    assert_equal "Speak plainly. Do not pad.", notes
    refute_includes notes, "Documentation for the human"
    refute_includes notes, "A heading that is also not identity"
  end

  # The file as it actually ships has to survive its own loader, or the rule
  # above is true of a fixture and false of production.
  def test_the_shipped_identity_file_still_yields_notes
    notes = personality.send(:load_identity)

    refute_empty notes, "data/IDENTITY.md now yields nothing — the loader ate the operator's tone notes"
    refute_includes notes, "<!--", "an HTML comment survived into the prompt"
  end
end
