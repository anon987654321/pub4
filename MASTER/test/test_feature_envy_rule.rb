# frozen_string_literal: true

require_relative "test_helper"
require "review/scan/rule_dsl"

# `rules.yml` describes this detector as a "single-method heuristic, same-file
# only" with a "genuine false-positive risk on generic-but-unrelated
# primitives", so the thresholds are the rule and each one is pinned from both
# sides. It fires when a method names one receiver at least four times, that
# receiver dominates, there are five or more receiver calls in total, and the
# method touches its own state less often than it touches the neighbour.
class TestFeatureEnvyRule < Minitest::Test
  def rule = Master::Review::Scan::Rules::FeatureEnvyRule.new

  def flags(source, path: "lib/thing.rb")
    rule.check(source, path:).map(&:message)
  end

  def test_it_flags_a_method_that_lives_in_another_object
    found = flags(<<~RUBY)
      def summarise
        order.total
        order.currency
        order.customer
        order.placed_at
        order.status
      end
    RUBY

    assert_equal 1, found.size
    assert_includes found.first, "order"
    assert_includes found.first, "5 times"
  end

  # Own state is the counterweight. A method that reaches a neighbour often but
  # its own instance more is doing its own work with help, which is not envy.
  #
  # Written first with four neighbour calls, which passed for the wrong reason:
  # four is below the floor below, so the floor exempted it and the counterweight
  # was never consulted. Deleting `count > local` from the rule left that version
  # green. Five calls clears the floor, so only the counterweight can spare this.
  def test_it_spares_a_method_that_touches_its_own_state_more
    assert_empty flags(<<~RUBY), "more own-state references than neighbour calls is not envy"
      def summarise
        order.total
        order.currency
        order.customer
        order.placed_at
        order.status
        @a = @b + @c + @d + @e + @f + @g
      end
    RUBY
  end

  # Below five receiver calls the sample is too small to call anything
  # dominant, which is what keeps ordinary two-line methods out.
  def test_it_spares_a_method_with_too_few_receiver_calls
    assert_empty flags(<<~RUBY)
      def summarise
        order.total
        order.currency
        order.customer
        order.placed_at
      end
    RUBY
  end

  # Spread across several collaborators there is no one object to move toward,
  # so the advice the message gives would have nowhere to point.
  def test_it_spares_calls_spread_across_several_collaborators
    assert_empty flags(<<~RUBY)
      def summarise
        order.total
        customer.name
        address.city
        payment.method
        shipment.eta
      end
    RUBY
  end

  def test_it_ignores_a_file_that_is_not_ruby
    assert_empty flags(<<~RUBY, path: "lib/thing.txt")
      def summarise
        order.total
        order.currency
        order.customer
        order.placed_at
        order.status
      end
    RUBY
  end

  def test_it_registers_under_the_id_the_dependency_graph_names
    assert_equal "FEATURE_ENVY", rule.id.to_s
  end
end
