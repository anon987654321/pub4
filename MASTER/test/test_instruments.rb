# frozen_string_literal: true

# My measurement code is wrong more often than my reasoning, and a wrong
# instrument is expensive because its output is plausible.
#
# On 2026-08-12 a hand-rolled method-length counter scored `def x = expr` as
# running to the next `end`, reported MASTER's longest method as 60 lines when
# it was 34, and made a tightly factored codebase read as needing a refactor.
# The same day, a verification regex with broken escaping reported zero matches
# for a pattern that had two. Neither was caught by a test; both would have been
# caught in seconds by a file whose right answers were already written down.

require "minitest/autorun"
require_relative "../tools/instruments"

class TestInstruments < Minitest::Test
  def self.report = @report ||= Pub4::Instruments.run

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

  # The endless-def case specifically, because that is the one that was got
  # wrong for real. Four methods, none of them long.
  def test_an_endless_def_is_not_a_long_method
    source = File.read(File.expand_path("../tools/fixtures/endless_defs.rb", __dir__))
    measured = Pub4::Instruments.measured(source)

    assert_equal 4, measured["public_methods"]
    assert_equal 1, measured["longest_method"],
                 "an endless method is being measured as if it ran to the next `end`"
  end

  # Comments are not length — the 2026-08-10 decision that made lint:spine and
  # [DENSITY] agree. If this flips, one of the two gates has drifted back.
  def test_comments_do_not_count_as_length
    source = File.read(File.expand_path("../tools/fixtures/documented_method.rb", __dir__))

    assert_equal 2, Pub4::Instruments.measured(source)["longest_method"]
  end

  # A fixture with no declared answers passes silently, which is the failure
  # this whole file exists to prevent.
  def test_a_fixture_that_declares_nothing_is_a_finding
    assert_empty Pub4::Instruments.declared("# frozen_string_literal: true\nclass A; end\n")
  end
end
