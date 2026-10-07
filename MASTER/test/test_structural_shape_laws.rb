# frozen_string_literal: true

require_relative "test_helper"
require "review/scan/rule_dsl"
require "prism"

# Five shape rules from structural_rules.rb that nothing named until now:
# FileLayoutRule, CyclomaticComplexityRule, DataClassRule, MiddleManRule and
# NestingDepthRule.
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

  # A private section is what `private` is for, so the methods under it are the
  # rule being obeyed. The line-based reading called the first of them a
  # violation and produced 261 findings across MASTER, every one of them a
  # correctly private method.
  def test_file_layout_spares_the_private_methods_under_the_marker
    assert_empty flags(Rules::FileLayoutRule.new, <<~RUBY)
      # frozen_string_literal: true
      class Thing
        def a; end

        private

        def b; end
        def c; end
      end
    RUBY
  end

  # Two ways to write a method that is still public below the marker, and both
  # are what the law forbids: re-open the scope, or define a singleton method,
  # which `private` does not reach.
  def test_file_layout_flags_a_scope_reopened_to_public
    found = flags(Rules::FileLayoutRule.new, <<~RUBY)
      # frozen_string_literal: true
      class Thing
        private

        def b; end

        public

        def c; end
      end
    RUBY

    assert_equal 1, found.size
    assert_includes found.first, "public method c after private marker"
  end

  def test_file_layout_flags_a_singleton_method_below_private
    found = flags(Rules::FileLayoutRule.new, <<~RUBY)
      # frozen_string_literal: true
      class Thing
        private

        def b; end

        def self.build; end
      end
    RUBY

    assert_equal 1, found.size
    assert_includes found.first, "def self.build below the private marker is still public"
  end

  # Visibility resets inside every class and module body, so a nested class's
  # public methods are not below the outer scope's marker.
  def test_file_layout_resets_visibility_in_a_nested_scope
    assert_empty flags(Rules::FileLayoutRule.new, <<~RUBY)
      # frozen_string_literal: true
      class Thing
        private

        def b; end

        class Inner
          def visible; end
        end
      end
    RUBY
  end

  # A shebang has to come first, so the header sits on the second line.
  def test_file_layout_accepts_the_header_under_a_shebang
    assert_empty flags(Rules::FileLayoutRule.new, "#!/usr/bin/env ruby\n# frozen_string_literal: true\nclass Thing\nend\n")
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

  # NESTING_DEPTH — depth over the AST, not over the margin.

  def ast_flags(source)
    Rules::NestingDepthRule.new.check_ast(Prism.parse(source).value, source, path: "lib/thing.rb").map { |f| f[:message] }
  end

  def test_nesting_depth_allows_four_levels
    assert_empty ast_flags(<<~RUBY)
      def call(a, b, c, d)
        if a
          if b
            if c
              if d
                true
              end
            end
          end
        end
      end
    RUBY
  end

  def test_nesting_depth_reports_the_fifth_level
    found = ast_flags(<<~RUBY)
      def call(a, b, c, d, e)
        if a
          if b
            if c
              if d
                if e
                  true
                end
              end
            end
          end
        end
      end
    RUBY

    assert_equal 1, found.size
    assert_includes found.first, "nesting depth exceeds 4"
  end

  # Blocks nest as surely as conditions do, and five `each`es are the commoner
  # half of this shape. A rule counting only `if` would spare it.
  def test_nesting_depth_counts_a_block
    refute_empty ast_flags(<<~RUBY)
      def call(rows)
        rows.each do |a|
          a.each do |b|
            b.each do |c|
              c.each do |d|
                d.each { |e| e }
              end
            end
          end
        end
      end
    RUBY
  end

  # Indentation is not depth. A module inside a module holding a class holding a
  # def is six columns in and branches nowhere, and a rule reading the margin
  # would fire on every namespaced file in this tree.
  def test_nesting_depth_spares_module_class_and_def
    assert_empty ast_flags(<<~RUBY)
      module A
        module B
          class C
            def d
              e
            end
          end
        end
      end
    RUBY
  end
end
