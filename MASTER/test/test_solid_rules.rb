# frozen_string_literal: true

require_relative "test_helper"
require "review/scan/rule_dsl"

# The four SOLID proxies — OpenClosedRule, LiskovRule, DependencyInversionRule,
# InterfaceSegregationRule. Until now nothing named any of them, and three of
# the four fire on nothing: measured over 2,470 Ruby files across all four
# trees, OPEN_CLOSED found 3 and the other three found 0.
#
# That number has two readings and no test could tell them apart. Either the
# tree has none of these shapes, or the detectors cannot see them — and a rule
# that cannot see its own subject looks identical from outside to a rule with
# nothing to report. Every test below therefore starts from a source the rule
# MUST flag, which settles it: all four can fire, so the silence is the sample.
#
# `rules.yml` calls each of these detectors a heuristic in its own words, so the
# exemptions matter as much as the detections and each is pinned beside its
# violation. A detector tested only for firing proves nothing about what it
# spares.
class TestSolidRules < Minitest::Test
  Rules = Master::Review::Scan::Rules

  def flags(rule, source)
    rule.check(source, path: "lib/thing.rb").map(&:message)
  end

  def assert_silent(rule, source, why)
    assert_empty flags(rule, source), why
  end

  # OPEN_CLOSED — a case that dispatches on type has to grow a branch for every
  # new type, which is the thing polymorphism exists to avoid.

  def test_open_closed_flags_a_three_branch_type_dispatch
    found = flags(Rules::OpenClosedRule.new, <<~RUBY)
      def render(node)
        case node.class
        when Header then draw_header(node)
        when Footer then draw_footer(node)
        when Body   then draw_body(node)
        end
      end
    RUBY

    assert_equal 1, found.size
    assert_includes found.first, "3 branches"
  end

  def test_open_closed_flags_an_is_a_chain
    found = flags(Rules::OpenClosedRule.new, <<~RUBY)
      def render(node)
        case
        when node.is_a?(Header) then 1
        when node.is_a?(Footer) then 2
        when node.is_a?(Body)   then 3
        end
      end
    RUBY

    assert_equal 1, found.size
  end

  # Two branches is an if/else wearing a case. The threshold is where the rule
  # decides a switch has become a type table.
  def test_open_closed_spares_a_two_branch_dispatch
    assert_silent Rules::OpenClosedRule.new, <<~RUBY, "two branches is not yet a type table"
      def render(node)
        case node.class
        when Header then 1
        when Footer then 2
        end
      end
    RUBY
  end

  # The common and important exemption: dispatching on a value is ordinary
  # branching, and flagging it would make every state machine a violation.
  def test_open_closed_spares_dispatch_on_a_value
    assert_silent Rules::OpenClosedRule.new, <<~RUBY, "a case over values is not a type switch"
      def label(status)
        case status
        when "open"   then "Open"
        when "closed" then "Closed"
        when "held"   then "On hold"
        end
      end
    RUBY
  end

  # LISKOV — a subclass that refuses the parent's contract, or narrows it.

  def test_liskov_flags_a_refused_bequest
    found = flags(Rules::LiskovRule.new, <<~RUBY)
      class Parent
        def render(a) = a
      end
      class Child < Parent
        def render(a) = raise NotImplementedError
      end
    RUBY

    assert_equal 1, found.size
    assert_includes found.first, "refuses the parent's contract"
  end

  def test_liskov_flags_a_subclass_that_demands_more_arguments
    found = flags(Rules::LiskovRule.new, <<~RUBY)
      class Parent
        def save(a) = a
      end
      class Child < Parent
        def save(a, b) = [a, b]
      end
    RUBY

    assert_equal 1, found.size
    assert_includes found.first, "requires 2 args, parent requires 1"
  end

  def test_liskov_spares_an_honest_override
    assert_silent Rules::LiskovRule.new, <<~RUBY, "same arity and a real body is what overriding is for"
      class Parent
        def render(a) = a
      end
      class Child < Parent
        def render(a) = a.upcase
      end
    RUBY
  end

  # An optional extra parameter widens what callers may pass rather than
  # narrowing it, so substitutability holds and the rule must stay quiet.
  def test_liskov_spares_an_added_optional_parameter
    assert_silent Rules::LiskovRule.new, <<~RUBY, "an optional argument widens the contract"
      class Parent
        def save(a) = a
      end
      class Child < Parent
        def save(a, b = nil) = [a, b]
      end
    RUBY
  end

  # The documented limit of a same-file heuristic, pinned so nobody reads
  # silence as a clean bill of health. Almost every real subclass in this
  # repository has its parent in another file, which is most of why the rule
  # reports nothing across 2,470 files.
  def test_liskov_cannot_see_a_parent_in_another_file
    assert_silent Rules::LiskovRule.new, <<~RUBY, "a parent outside the file is invisible — a known limit, not a clean result"
      class Child < SomeParentElsewhere
        def render(a) = raise NotImplementedError
      end
    RUBY
  end

  # DEPENDENCY_INVERSION — a constructor that builds its own collaborator.

  def test_dependency_inversion_flags_a_hardcoded_collaborator
    found = flags(Rules::DependencyInversionRule.new, <<~RUBY)
      class Checkout
        def initialize
          @payment = PaymentService.new
        end
      end
    RUBY

    assert_equal 1, found.size
    assert_includes found.first, "PaymentService.new hardcoded"
  end

  def test_dependency_inversion_spares_an_injected_collaborator
    assert_silent Rules::DependencyInversionRule.new, <<~RUBY, "injection is the fix this rule asks for"
      class Checkout
        def initialize(payment_service)
          @payment = payment_service
        end
      end
    RUBY
  end

  # The suffix list is what makes this a rule about collaborators rather than a
  # ban on constructing anything.
  def test_dependency_inversion_spares_an_ordinary_object
    assert_silent Rules::DependencyInversionRule.new, <<~RUBY, "not every .new is a hidden dependency"
      class Checkout
        def initialize
          @items = Array.new
        end
      end
    RUBY
  end

  def test_dependency_inversion_looks_only_at_the_constructor
    assert_silent Rules::DependencyInversionRule.new, <<~RUBY, "building a collaborator inside a method is not constructor coupling"
      class Checkout
        def refund
          PaymentService.new.refund
        end
      end
    RUBY
  end

  # INTERFACE_SEGREGATION — a module wide enough that its includers cannot want
  # all of it, and enough includers to prove the point.

  def test_interface_segregation_flags_a_wide_module_with_two_includers
    found = flags(Rules::InterfaceSegregationRule.new, fat_module(9, includers: 2))

    assert_equal 1, found.size
    assert_includes found.first, "9 public methods"
    assert_includes found.first, "included by 2 classes"
  end

  def test_interface_segregation_spares_a_module_at_the_limit
    assert_silent Rules::InterfaceSegregationRule.new, fat_module(8, includers: 2),
                  "eight is the limit, not the violation"
  end

  # One includer cannot show that the interface is too wide for its clients —
  # that is a big module, which is a different rule's business.
  def test_interface_segregation_spares_a_wide_module_with_one_includer
    assert_silent Rules::InterfaceSegregationRule.new, fat_module(9, includers: 1),
                  "a single includer proves nothing about segregation"
  end

  private

  def fat_module(method_count, includers:)
    methods = (1..method_count).map { |n| "  def m#{n}; end" }.join("\n")
    classes = (1..includers).map { |n| "class C#{n}\n  include Fat\nend" }.join("\n")
    "module Fat\n#{methods}\nend\n#{classes}\n"
  end
end
