# frozen_string_literal: true

require_relative "test_helper"
require "prism"

# CodeMetrics.public_method_count is what NO_GOD_CLASS reads, and it read
# visibility off a stop marker: the walk ended at the first `private` or
# `protected`. Every case below is a way Ruby says "public" that the stop marker
# could not see, and each was an undercount — so the god-class rule was reading
# a floor rather than a surface. Measured across MASTER's lib, law and tools:
# 2,588 public methods before, 2,663 after, twenty classes changed, and
# Ground::RuntimeCatalog went from 0 to 14 because every one of its methods is a
# class method written below a `private`.
class TestVisibilitySemantics < Minitest::Test
  def count(source)
    parsed = Prism.parse(source)

    assert parsed.success?, parsed.errors.map(&:message).join("\n")
    Master::Review::Scan::CodeMetrics.public_method_count(parsed.value.statements.body.first)
  end

  # `public` re-opens the scope. The old walk had already stopped.
  def test_public_reopens_the_scope
    assert_equal 2, count(<<~RUBY)
      class Example
        def first; end

        private

        def hidden; end

        public

        def second; end
      end
    RUBY
  end

  # `protected` is a visibility, not the end of the class.
  def test_protected_is_not_the_end_of_the_body
    assert_equal 1, count(<<~RUBY)
      class Example
        protected

        def guarded; end

        public

        def open; end
      end
    RUBY
  end

  # `private` moves the instance-method default and never reaches the singleton
  # stream, so a class method below it is still public API.
  def test_private_does_not_reach_a_singleton_method
    assert_equal 1, count(<<~RUBY)
      class Example
        private

        def self.api; end
        def internal; end
      end
    RUBY
  end

  # And private_class_method is what does reach it. Two public here, not one:
  # `initialize` is defined above the bare `private` and stays public.
  def test_private_class_method_reaches_the_singleton_stream
    assert_equal 2, count(<<~RUBY)
      class Example
        def self.api; end
        def self.internal; end
        def instance_api; end

        private_class_method :internal
        private
      end
    RUBY
  end

  # The named forms are retroactive: they sit below the def they change, which
  # is why counting takes two passes rather than one.
  def test_named_visibility_applies_backwards_without_moving_the_default
    assert_equal 2, count(<<~RUBY)
      class Example
        def first; end
        def second; end

        private :first
        public :second

        def third; end
      end
    RUBY
  end

  # `private def x` is a CallNode wrapping the DefNode, so neither form was
  # counted at all before — public or private.
  def test_inline_modifiers_reach_one_definition_each
    assert_equal 1, count(<<~RUBY)
      class Example
        private def hidden; end
        public def visible; end
      end
    RUBY
  end

  # `class << self` carries its own default, and the outer one does not leak in.
  def test_a_singleton_class_has_its_own_default
    assert_equal 1, count(<<~RUBY)
      class Example
        private

        class << self
          private
          def hidden; end

          public
          def api; end
        end
      end
    RUBY
  end

  # `class << Other` and `def Other.x` reopen something else. Neither belongs to
  # this class's surface.
  def test_another_objects_singleton_is_not_this_class
    assert_equal 1, count(<<~RUBY)
      class Example
        def api; end
        def Other.elsewhere; end

        class << Other
          def also_elsewhere; end
        end
      end
    RUBY
  end
end
