# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require_relative "gate_fixture"
require_relative "../../../MASTER/gates/lib/source/dialect_purity"

# Four dialects that must stay apart, and one map that owns the accents.
#
# brgen is social, amber is luxury, bsdports keeps the wscons square corners and
# MASTER's face is its own. The failure the gate exists for is a vertical
# re-setting --accent for itself, which takes the colour out of brgen's accent
# map and puts it somewhere nothing else reads.
#
# The fixture tree is passed as root:, so every file the gate reads comes from it.
class DialectPurityGateTest < Minitest::Test
  include GateFixture

  GATE = Deploy::DialectPurityGate

  MASTER_RULES = <<~YAML
    design_system:
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
      vertical_accent_ink: "#110f19"
  YAML

  DESIGN_DOC = "Dialects: social, luxury, openbsd_wscons, face_root.\n" \
           "Flat rule: no box-shadow anywhere.\n" \
           "Vertical accents come from vertical_accents, through _vertical_shell.\n"

  BRGEN = <<~'SCSS'
    @use "sass:list";
    $vertical-accents: (marketplace: (#1b7f4f), dating: (#b3315a));
    :root { @include x.brgen-old-dark-tokens; }
    @each $v, $c in $vertical-accents {
      body.vertical-#{$v} { --accent: #{list.nth($c, 1)}; }
    }
    body.vertical-dating .dating { color: var(--accent); }
  SCSS

  BSDPORTS = ":root {\n  color-scheme: light;\n  --radius-pill: 0;\n  --radius-card: 0;\n}\n"

  def sound_tree(dir)
    plant(dir, "MASTER/data/rules.yml", MASTER_RULES)
    plant(dir, "RAILS/shared/README.md", DESIGN_DOC)
    plant(dir, "RAILS/brgen/app/assets/stylesheets/application.scss", BRGEN)
    plant(dir, "RAILS/bsdports/app/assets/stylesheets/application.scss", BSDPORTS)
    plant(dir, "RAILS/amber/app/assets/stylesheets/application.scss", "// luxury palette\n")
  end

  def gate_over
    Dir.mktmpdir do |dir|
      sound_tree(dir)
      yield dir
      GATE.run(root: dir)
    end
  end

  def test_the_sound_tree_passes_and_reads_every_stylesheet
    result = gate_over { nil }

    assert result.ok?, result.failures.join(", ")
    assert_operator result.checks_ran, :>, 10
  end

  def test_a_vertical_setting_its_own_accent_fails
    result = gate_over do |dir|
      plant(dir, "RAILS/brgen/app/assets/stylesheets/application.scss",
            BRGEN + "body.vertical-dating .dating { --accent: #b3315a; }\n")
    end

    refute result.ok?, "a vertical re-setting --accent passed"
    assert_match(/application\.scss:8 body\.vertical-dating \.dating re-sets --accent \(the accent map only\)/,
                 result.failures.first)
  end

  def test_brgen_without_its_dialect_on_root_fails
    result = gate_over do |dir|
      plant(dir, "RAILS/brgen/app/assets/stylesheets/application.scss",
            BRGEN.sub("@include x.brgen-old-dark-tokens;", "--bg: #000;"))
    end

    refute result.ok?, "brgen without brgen-old on :root passed"
    assert_match(/brgen's :root does not include the brgen-old tokens/, result.failures.first)
  end

  def test_bsdports_with_rounded_corners_fails
    result = gate_over do |dir|
      plant(dir, "RAILS/bsdports/app/assets/stylesheets/application.scss", BSDPORTS.sub("--radius-card: 0;", "--radius-card: 8px;"))
    end

    refute result.ok?, "bsdports without the wscons radii on :root passed"
    assert_match(/bsdports' :root does not zero the wscons radii/, result.failures.first)
  end

  # An engine that grows a stylesheet of its own again is held to the same map:
  # when the verticals first moved to engines, a glob of the host alone read two
  # files and called that the dialect.
  def test_a_vertical_sheet_under_an_engine_is_read_too
    result = gate_over do |dir|
      plant(dir, "RAILS/brgen/engines/tv/app/assets/stylesheets/_vertical_tv.scss",
            ".tv { --accent: #226; }\n")
    end

    refute result.ok?, "an engine's vertical stylesheet was not read"
    assert_match(/_vertical_tv\.scss:1 \.tv re-sets --accent/, result.failures.first)
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
      plant(dir, "MASTER/data/rules.yml", MASTER_RULES.sub(%(    dating:\n      accent: "#b3315a"\n), ""))
    end

    refute result.ok?, "a missing vertical accent passed"
    assert_match(/vertical_accents\.dating missing/, result.failures.first)
  end

  def test_a_dialect_missing_from_master_design_fails
    result = gate_over do |dir|
      plant(dir, "MASTER/data/rules.yml", MASTER_RULES.sub(/  luxury:\n    accent: "#b08d57"\n/, ""))
    end

    refute result.ok?, "a missing dialect passed"
    assert_match(/MASTER design_system missing luxury/, result.failures.first)
  end

  def test_a_design_doc_that_lost_the_flat_rule_fails
    result = gate_over do |dir|
      plant(dir, "RAILS/shared/README.md", DESIGN_DOC.sub(/Flat rule.*\n/, ""))
    end

    refute result.ok?, "a design doc without the flat rule passed"
    assert_match(/lost the Flat rule/, result.failures.first)
  end

  def test_a_missing_master_rules_fails_rather_than_passing_empty
    result = gate_over do |dir|
      File.delete(File.join(dir, "MASTER/data/rules.yml"))
    end

    refute result.ok?, "missing MASTER design rules passed"
    assert_match(/missing MASTER\/data\/rules\.yml design_system/, result.failures.first)
  end
end
