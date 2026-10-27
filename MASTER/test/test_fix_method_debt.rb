# frozen_string_literal: true

require_relative "test_helper"
require "fix/method_debt"

# How a finding on a def line is matched to the same method at the base, and
# what counts as the method getting worse.
class TestFixMethodDebt < Minitest::Test
  Debt = Master::Fix::MethodDebt

  SOURCE = "module Outer\n  class Inner\n    def call(x)\n      x\n    end\n\n    def self.build\n    end\n  end\nend\n"

  def row(line, message, law: "ABC_SIZE") = { law:, line:, message: }

  def test_methods_are_keyed_by_their_def_line_and_qualified_name
    methods = Debt.methods_by_line(SOURCE)

    assert_equal "Outer::Inner#call", methods[3].key
    assert_equal 3..5, methods[3].range
    assert_equal "Outer::Inner.build", methods[7].key
    assert_nil methods[4]
  end

  def test_a_moved_method_with_the_same_measure_is_not_worse
    moved = "# header\n#{SOURCE}"
    debt = Debt.new(source: moved, base_source: SOURCE,
                    base_findings: [row(3, "ABC size 45.2 for #call (A=1 B=2 C=3, ratchet 40)")])

    refute debt.worse?(row(4, "ABC size 45.2 for #call (A=1 B=2 C=3, ratchet 40)"))
    assert debt.worse?(row(4, "ABC size 47.0 for #call (A=1 B=4 C=3, ratchet 40)"))
    refute debt.worse?(row(4, "ABC size 41.0 for #call (A=1 B=1 C=3, ratchet 40)"))
  end

  def test_a_rubocop_measure_is_the_figure_before_its_limit
    too_high = "rubocop: Metrics/AbcSize — Assignment Branch Condition size for call is too high."
    abc = ->(measure) { row(3, "#{too_high} [#{measure}]", law: "rubocop") }
    debt = Debt.new(source: SOURCE, base_source: SOURCE, base_findings: [abc.call("<10, 25, 5> 27.39/17")])

    refute debt.worse?(abc.call("<12, 24, 5> 27.30/17"))
    assert debt.worse?(abc.call("<9, 27, 5> 28.9/17"))
    assert debt.worse?(row(3, "rubocop: Metrics/MethodLength — Method has too many lines. [25/10]", law: "rubocop")),
           "another cop on the same method is a new finding"
  end
end
