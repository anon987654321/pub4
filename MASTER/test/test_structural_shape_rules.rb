# frozen_string_literal: true

require_relative "test_helper"
require "review/scan/rule_dsl"

# Four shape rules from structural_rules.rb that nothing named until now:
# FileLayoutRule, CyclomaticComplexityRule, DataClassRule, MiddleManRule.
#
# Each is tested the way law/ tests its own — a source it must flag and a source
# it must not — because a detector proved only to fire says nothing about what it
# spares, and every one of these has a threshold or an exemption that is the
# whole rule.
class TestStructuralShapeRules < Minitest::Test
  Rules = Master::Review::Scan::Rules

  def flags(rule, source, path: "lib/thing.rb")
    rule.check(source, path:).map(&:message)
  end

  # FILE_LAYOUT — the header and the position of the private marker.

  def test_file_layout_flags_a_missing_frozen_header
    found = flags(Rules::FileLayoutRule.new, "class Thing\nend\n")

    assert_equal 1, found.size
    assert_includes found.first, "frozen_string_literal"
  end

  def test_file_layout_accepts_the_header_on_the_first_line
    assert_empty flags(Rules::FileLayoutRule.new, "# frozen_string_literal: true\nclass Thing\nend\n")
  end

  def test_file_layout_flags_a_public_method_below_the_private_marker
    found = flags(Rules::FileLayoutRule.new, <<~RUBY)
      # frozen_string_literal: true
      class Thing
        def a; end

        private

        def b; end
      end
    RUBY

    assert_equal 1, found.size
    assert_includes found.first, "after private marker"
  end

  # initialize, to_s and inspect below private are the documented exemption:
  # they are conventional positions, not a public method hiding in the wrong
  # half of the file.
  def test_file_layout_spares_the_conventional_names_below_private
    assert_empty flags(Rules::FileLayoutRule.new, <<~RUBY)
      # frozen_string_literal: true
      class Thing
        private

        def initialize; end
        def to_s; end
        def inspect; end
      end
    RUBY
  end

  def test_file_layout_ignores_a_file_that_is_not_ruby
    assert_empty flags(Rules::FileLayoutRule.new, "class Thing\nend\n", path: "lib/thing.txt")
  end

  # CYCLOMATIC_COMPLEXITY — one plus every branching node, per method.

  def test_cyclomatic_complexity_flags_a_method_over_the_limit
    branches = (1..10).map { |n| "  return :a#{n} if x == #{n}" }.join("\n")
    found = flags(Rules::CyclomaticComplexityRule.new, "def wide(x)\n#{branches}\nend\n")

    assert_equal 1, found.size
    assert_includes found.first, "complexity 11"
    assert_includes found.first, "wide"
  end

  # Exactly at the limit is not over it, and the boundary is where a threshold
  # rule is most likely to be off by one.
  def test_cyclomatic_complexity_spares_a_method_at_the_limit
    branches = (1..9).map { |n| "  return :a#{n} if x == #{n}" }.join("\n")

    assert_empty flags(Rules::CyclomaticComplexityRule.new, "def edge(x)\n#{branches}\nend\n")
  end

  # Twelve terms is eleven `||` operators, so complexity is twelve. Written with
  # ten terms first, which is nine operators and lands exactly on the limit —
  # the rule was right and the test was wrong, which is the arithmetic worth
  # leaving written down.
  def test_cyclomatic_complexity_counts_boolean_operators_as_branches
    conds = (1..12).map { |n| "x == #{n}" }.join(" || ")
    found = flags(Rules::CyclomaticComplexityRule.new, "def orred(x)\n  #{conds}\nend\n")

    assert_equal 1, found.size, "each || is a path through the method and has to count"
    assert_includes found.first, "complexity 12"
  end

  # DATA_CLASS — accessors and nothing else.

  def test_data_class_flags_accessors_without_behaviour
    found = flags(Rules::DataClassRule.new, <<~RUBY)
      class Point
        attr_reader :x
        attr_reader :y
      end
    RUBY

    assert_equal 1, found.size
    assert_includes found.first, "Point"
    assert_includes found.first, "no behavior"
  end

  def test_data_class_spares_a_class_that_does_something
    assert_empty flags(Rules::DataClassRule.new, <<~RUBY)
      class Point
        attr_reader :x
        attr_reader :y

        def distance = Math.sqrt((x * x) + (y * y))
      end
    RUBY
  end

  # A constructor and the two printing methods are not behaviour — a Struct has
  # them too, which is the rule's own point.
  def test_data_class_does_not_count_initialize_or_printing_as_behaviour
    found = flags(Rules::DataClassRule.new, <<~RUBY)
      class Point
        attr_reader :x
        attr_reader :y

        def initialize(x, y) = (@x, @y = x, y)
        def to_s = "\#{x},\#{y}"
      end
    RUBY

    assert_equal 1, found.size
  end

  def test_data_class_spares_a_single_accessor
    assert_empty flags(Rules::DataClassRule.new, "class Wrapper\n  attr_reader :inner\nend\n"),
                 "one accessor is a wrapper, not a data class"
  end

  # MIDDLE_MAN — a class whose every method forwards to the same object.

  def test_middle_man_flags_a_class_that_only_forwards
    found = flags(Rules::MiddleManRule.new, <<~RUBY)
      class Facade
        def initialize(inner) = @inner = inner
        def a = @inner.a
        def b = @inner.b
        def c = @inner.c
      end
    RUBY

    assert_equal 1, found.size
    assert_includes found.first, "forwards all 3 methods"
  end

  # The constructor holds the delegate rather than forwarding to it. Counting it
  # would exempt every wrapper that has one, which is all of them.
  def test_middle_man_does_not_count_the_constructor_toward_the_minimum
    assert_empty flags(Rules::MiddleManRule.new, <<~RUBY)
      class Facade
        def initialize(inner) = @inner = inner
        def a = @inner.a
        def b = @inner.b
      end
    RUBY
  end

  def test_middle_man_spares_a_class_with_one_method_of_its_own
    assert_empty flags(Rules::MiddleManRule.new, <<~RUBY)
      class Facade
        def initialize(inner) = @inner = inner
        def a = @inner.a
        def b = @inner.b
        def c = compute + 1
      end
    RUBY
  end

  # Forwarding to two different objects is coordination, which is a reason to
  # exist. The rule is about the class that adds a name and nothing else.
  def test_middle_man_spares_forwarding_to_more_than_one_object
    assert_empty flags(Rules::MiddleManRule.new, <<~RUBY)
      class Facade
        def initialize(a, b) = (@a, @b = a, b)
        def one = @a.one
        def two = @b.two
        def three = @a.three
      end
    RUBY
  end
end
