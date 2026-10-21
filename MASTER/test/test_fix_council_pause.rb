# frozen_string_literal: true

require_relative "test_helper"
require "tmpdir"

# The council is off inside /fix until it is asked for, and the run ends with an offer to convene it. A
# council fault used to cost a whole run: every persona raised, and the repair stage ran beside the wreck.
class TestFixCouncilPause < Minitest::Test
  Clock = Master::Review::LLMDispatcher::PassClock

  def test_the_council_is_off_without_a_request
    refute Clock.council_enabled?(env: {})
    refute Clock.council_enabled?(env: { "MASTER_FIX_COUNCIL" => "0" })
  end

  def test_asking_for_the_council_turns_it_on
    assert Clock.council_enabled?(env: { "MASTER_FIX_COUNCIL" => "1" })
  end

  def test_the_offer_names_the_command_that_convenes_it
    assert_includes Master::CLI::Pipeline::Pass::COUNCIL_OFFER, "/critique"
  end

  def test_the_council_reads_a_diff_with_non_ascii_text_as_text
    Dir.mktmpdir("council-diff") do |root|
      git = ->(*argv) { assert system("git", *argv, chdir: root, out: File::NULL, err: File::NULL) }
      [%w[init -q], %w[config user.email t@example.test], %w[config user.name t]].each { |argv| git.call(*argv) }
      File.write(File.join(root, "note.txt"), "one\n")
      git.call("add", "note.txt")
      git.call("commit", "-q", "-m", "base")
      File.write(File.join(root, "note.txt"), "to — på norsk\n")

      artifact = Master::CLI::CouncilCrit.diff_artifact(root, scope: "diff")

      assert_equal Encoding::UTF_8, artifact.encoding
      assert_includes "prompt: #{artifact}", "på norsk"
    end
  end

  def test_the_mode_line_says_the_council_waits_for_a_request
    spec = { name: "strict", council: true, scan_profile: "full", max_fix_passes: 15 }

    assert_includes Master::Ground::ModePosture.new(root: Master::ROOT).line(spec), "council on request"
  end
end
