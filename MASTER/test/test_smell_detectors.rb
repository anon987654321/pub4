# frozen_string_literal: true

require_relative "test_helper"
require "review/scan/rule_dsl"

# The four detectors from TODO.md's "Rule and AST-detector backlog". Each is
# tested the way law/ tests its own: one source it must flag, and one it must
# not, because a detector that only fires proves nothing about what it exempts —
# and every exemption below is a false positive that was measured against this
# tree before it was written down.
class TestSmellDetectors < Minitest::Test
  def findings(rule, source, path: "lib/thing.rb")
    rule.check(source, path:).map(&:message)
  end

  def refute_flagged(rule, source, path: "lib/thing.rb")
    assert_empty findings(rule, source, path:)
  end

  # BOOLEAN_TRAP

  def boolean_trap = Master::Review::Scan::Rules::BooleanTrapRule.new

  def test_boolean_trap_flags_a_positional_boolean_default
    found = findings(boolean_trap, "def shadow_lift(image, preserve_blacks = true)\n  image\nend\n")

    assert_equal 1, found.size
    assert_match(/preserve_blacks:/, found.first)
  end

  def test_boolean_trap_exempts_a_keyword
    refute_flagged boolean_trap, "def shadow_lift(image, preserve_blacks: true)\n  image\nend\n"
  end

  def test_boolean_trap_exempts_a_non_boolean_default
    refute_flagged boolean_trap, "def shadow_lift(image, amount = 0.5)\n  image\nend\n"
  end

  # DATA_CLUMPS

  def data_clumps = Master::Review::Scan::Rules::DataClumpsRule.new

  CLUMP = <<~RUBY
    def write(title, summary, author, path)
      [title, summary, author, path]
    end

    def preview(title, summary, author)
      [title, summary, author]
    end

    def publish(title, summary, author, at)
      [title, summary, author, at]
    end
  RUBY

  def test_data_clumps_flags_three_parameters_riding_together
    found = findings(data_clumps, CLUMP)

    assert_equal 1, found.size, "one clump should be one finding, not one per window"
    assert_match(/title, summary, author travel together through 3 signatures/, found.first)
  end

  # check_ast(ast, code, path:) implemented nine times is a contract, not a
  # clump. This was 33 of the 81 findings the first version reported.
  def test_data_clumps_exempts_one_interface_implemented_many_times
    source = 3.times.map { |i| "def check#{i}(ast, code, path)\n  [ast, code, path]\nend\n" }.join("\n")

    refute_flagged data_clumps, source
  end

  def test_data_clumps_ignores_two_signatures
    source = "def write(title, summary, author)\n  1\nend\n\ndef preview(title, summary, author, x)\n  2\nend\n"

    refute_flagged data_clumps, source
  end

  # TYPE_IN_NAME

  def type_in_name = Master::Review::Scan::Rules::TypeInNameRule.new

  def test_type_in_name_flags_a_parameter_that_names_its_type
    found = findings(type_in_name, "def speak(text_str)\n  text_str\nend\n")

    assert_equal 1, found.size
    assert_match(/parameter text_str/, found.first)
  end

  def test_type_in_name_flags_a_local_and_an_ivar
    found = findings(type_in_name, "def build\n  id_str = 1\n  @args_array = [id_str]\nend\n")

    assert_equal 2, found.size
  end

  def test_type_in_name_exempts_the_conversion_protocol
    refute_flagged type_in_name, "def to_hash\n  {}\nend\n\ndef from_hash(other)\n  other\nend\n"
  end

  # A digest is spelled _hash too, and renaming prev_hash to prev loses the only
  # thing the name said.
  def test_type_in_name_exempts_a_digest
    refute_flagged type_in_name, "def stable_hash(text)\n  text\nend\n\ndef last_enacted_hash\n  1\nend\n"
  end

  def test_type_in_name_exempts_a_domain_noun
    refute_flagged type_in_name, "def allow_list\n  []\nend\n"
  end

  def test_type_in_name_leaves_tests_alone
    refute_flagged type_in_name,
                   "def test_a_query_string_is_parsed\n  1\nend\n",
                   path: "test/thing_test.rb"
  end

  # NUMBERED_NAME

  def numbered_name = Master::Review::Scan::Rules::NumberedNameRule.new

  def test_numbered_name_flags_numbered_siblings
    found = findings(numbered_name, "def mix_v7\n  1\nend\n\ndef mix_v8\n  2\nend\n")

    assert_equal 2, found.size
    assert_match(/mix_v7 sits beside mix_v8/, found.first)
  end

  # A lone number in a name is usually a fact about the world: an 1176 is a
  # compressor, a Fairchild 670 is a compressor, an STC-8 is a microphone.
  def test_numbered_name_exempts_a_number_with_no_sibling
    refute_flagged numbered_name, "def fet1176(signal)\n  signal\nend\n\ndef fairchild670(signal)\n  signal\nend\n"
  end

  def test_numbered_name_exempts_a_standard
    refute_flagged numbered_name, "def sha256(x)\n  x\nend\n\ndef sha512(x)\n  x\nend\n"
  end
end
