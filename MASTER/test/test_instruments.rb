# frozen_string_literal: true

# My measurement code is wrong more often than my reasoning, and a wrong
# instrument is expensive because its output is plausible.
#
# A method-length counter that scores `def x = expr` as running to the next
# `end`, or a regex with broken escaping that reports zero matches, is caught in
# seconds by a fixture whose right answers are already written down.

require "minitest/autorun"
require_relative "../tools/instruments"

class TestInstruments < Minitest::Test
  def self.report = @report ||= Operator::Instruments.run

  def setup
    @report = self.class.report
  end

  def test_the_implementation_agrees_with_the_declared_answers
    disagreements = @report["findings"].map { |row| "#{row['fixture']}: #{row['message']}" }

    assert_empty disagreements,
                 "the counter and the fixture disagree. One of them is wrong — work out which " \
                 "before changing either:\n  #{disagreements.join("\n  ")}"
  end

  def test_there_are_answers_to_check
    assert_operator @report["fixtures"], :>=, 3, "only #{@report['fixtures']} fixtures found"
    assert_operator @report["checks"], :>=, 9,
                    "only #{@report['checks']} declared answers checked — a fixture lost its " \
                    "`# instrument:` header and is being measured against nothing"
  end

  # The endless-def case specifically: four methods, none of them long.
  def test_an_endless_def_is_not_a_long_method
    source = File.read(File.expand_path("fixtures/endless_defs.rb", __dir__))
    measured = Operator::Instruments.measured(source)

    assert_equal 4, measured["public_methods"]
    assert_equal 1, measured["longest_method"],
                 "an endless method is being measured as if it ran to the next `end`"
  end

  # Comments are not length, which is what keeps lint:spine and [DENSITY]
  # agreeing. If this flips, one of the two checks has drifted.
  def test_comments_do_not_count_as_length
    source = File.read(File.expand_path("fixtures/documented_method.rb", __dir__))

    assert_equal 2, Operator::Instruments.measured(source)["longest_method"]
  end

  # A fixture with no declared answers passes silently, which is the failure
  # this whole file exists to prevent.
  def test_a_fixture_that_declares_nothing_is_a_finding
    assert_empty Operator::Instruments.declared("# frozen_string_literal: true\nclass A; end\n")
  end
end
