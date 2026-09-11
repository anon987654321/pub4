# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require_relative "gate_fixture"
require_relative "../../gates/lib/source/dialect_purity"

# Four dialects that must stay apart, and one map that owns the accents.
#
# brgen is social, amber is luxury, bsdports is the OpenBSD console green and
# MASTER's face is its own. The failure the gate exists for is a vertical
# stylesheet re-setting --accent for itself, which takes the colour out of
# _vertical_shell's map and puts it somewhere nothing else reads.
#
# The gate resolves every file it reads from constants fixed at load time, so
# the fixture tree is installed by rewriting RAILS, TOKENS and WIRING.
class DialectPurityGateTest < Minitest::Test
  include GateFixture

  GATE = Deploy::DialectPurityGate

  TOKENS = <<~YAML
    social:
      accent: "#1b7f4f"
    luxury:
      accent: "#b08d57"
    openbsd_wscons:
      fg: "#63c363"
    face_root:
      bg: "#17161c"
    vertical_accents:
      marketplace:
        accent: "#1b7f4f"
      dating:
        accent: "#b3315a"
  YAML

  WIRING = "Dialects: social, luxury, openbsd_wscons, face_root.\n" \
           "Flat rule: no box-shadow anywhere.\n" \
           "Vertical accents come from vertical_accents, through _vertical_shell.\n"

  def sound_tree(dir)
    plant(dir, "RAILS/shared/design_tokens.yml", TOKENS)
    plant(dir, "RAILS/shared/WIRING_NOTES.md", WIRING)
    plant(dir, "RAILS/brgen/app/assets/stylesheets/_vertical_shell.scss",
          "$vertical-accents: (marketplace: #1b7f4f, dating: #b3315a);\n")
    plant(dir, "RAILS/brgen/app/assets/stylesheets/_vertical_dating.scss",
          ".dating { color: var(--accent); }\n")
    plant(dir, "RAILS/brgen/app/assets/stylesheets/_root.scss", ":root { --brgen-old: 1; }\n")
    plant(dir, "RAILS/bsdports/app/assets/stylesheets/application.scss", ":root { --fg: #63c363; }\n")
    plant(dir, "RAILS/amber/app/assets/stylesheets/_variables.scss", "// luxury palette\n")
  end

  def gate_over
    Dir.mktmpdir do |dir|
      sound_tree(dir)
      yield dir
      rails = File.join(dir, "RAILS")
      with_constants(GATE, RAILS: rails,
                           TOKENS: File.join(rails, "shared", "design_tokens.yml"),
                           WIRING: File.join(rails, "shared", "WIRING_NOTES.md")) { GATE.run }
    end
  end

  def test_the_sound_tree_passes_and_reads_every_stylesheet
    result = gate_over { nil }

    assert result.ok?, result.failures.join(", ")
    assert_operator result.checks_ran, :>, 10
  end

  def test_a_vertical_sheet_setting_its_own_accent_fails
    result = gate_over do |dir|
      plant(dir, "RAILS/brgen/app/assets/stylesheets/_vertical_dating.scss",
            ".dating { --accent: #b3315a; }\n")
    end

    refute result.ok?, "a vertical re-setting --accent passed"
    assert_match(/_vertical_dating\.scss re-sets --accent \(shell only\)/, result.failures.first)
  end

  # The verticals are engines, and their stylesheets moved with them. Globbing
  # the host alone left this check reading two files and calling that the
  # dialect.
  def test_a_vertical_sheet_under_an_engine_is_read_too
    result = gate_over do |dir|
      plant(dir, "RAILS/brgen/engines/tv/app/assets/stylesheets/_vertical_tv.scss",
            ".tv { --accent: #226; }\n")
    end

    refute result.ok?, "an engine's vertical stylesheet was not read"
    assert_match(/_vertical_tv\.scss re-sets --accent/, result.failures.first)
  end

  def test_twitter_blue_anywhere_in_the_family_fails
    result = gate_over do |dir|
      plant(dir, "RAILS/shared/app/assets/stylesheets/_links.scss", "a { color: #1d9bf0; }\n")
    end

    refute result.ok?, "twitter blue passed"
    assert_match(%r{twitter blue in shared/app/assets/stylesheets/_links\.scss}, result.failures.first)
  end

  def test_a_missing_vertical_accent_entry_fails
    result = gate_over do |dir|
      plant(dir, "RAILS/shared/design_tokens.yml", TOKENS.sub(%(  dating:\n    accent: "#b3315a"\n), ""))
    end

    refute result.ok?, "a missing vertical accent passed"
    assert_match(/vertical_accents\.dating missing/, result.failures.first)
  end

  def test_a_dialect_missing_from_the_tokens_fails
    result = gate_over do |dir|
      plant(dir, "RAILS/shared/design_tokens.yml", TOKENS.sub(/luxury:\n  accent: "#b08d57"\n/, ""))
    end

    refute result.ok?, "a missing dialect passed"
    assert_match(/design_tokens missing luxury/, result.failures.first)
  end

  def test_wiring_notes_that_lost_the_flat_rule_fail
    result = gate_over do |dir|
      plant(dir, "RAILS/shared/WIRING_NOTES.md", WIRING.sub(/Flat rule.*\n/, ""))
    end

    refute result.ok?, "WIRING_NOTES without the flat rule passed"
    assert_match(/lost Flat rule/, result.failures.first)
  end

  def test_a_missing_tokens_file_fails_rather_than_passing_empty
    result = gate_over do |dir|
      File.delete(File.join(dir, "RAILS/shared/design_tokens.yml"))
    end

    refute result.ok?, "a missing design_tokens.yml passed"
    assert_match(/missing design_tokens\.yml/, result.failures.first)
  end
end
