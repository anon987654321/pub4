# frozen_string_literal: true

require_relative "test_helper"

# Result::Err's two mixins, neither of which had a test.
#
# ErrClassification is the more interesting one, because it was wrong in a way
# no test could have caught by accident: it classified five of Result's fourteen
# categories, so `rate_limit.retriable?` was false. Nothing asks yet — neither
# predicate has a caller in lib/ — which is exactly why nobody noticed, and why
# the shape of the eventual bug would have been a retry loop that quietly does
# not retry.
class TestErrClassification < Minitest::Test
  R = Master::Result
  C = Master::Result::ErrClassification

  def err(category) = R.err("boom", category:)

  # --- the partition ------------------------------------------------------

  # The property that was broken. A category added to CATEGORIES and to neither
  # list is the same defect returning.
  def test_every_declared_category_is_classified
    unclassified = R::CATEGORIES.keys.reject { |category| err(category).classified? }

    assert_empty unclassified,
                 "these answer false to both retriable? and permanent?, so a caller " \
                 "asking either question is told the wrong thing: #{unclassified.inspect}"
  end

  def test_no_category_is_both
    both = C::RETRIABLE & C::PERMANENT

    assert_empty both, "a category cannot be worth retrying and not worth retrying: #{both.inspect}"
  end

  def test_neither_list_names_a_category_that_does_not_exist
    orphans = (C::RETRIABLE + C::PERMANENT) - R::CATEGORIES.keys

    assert_empty orphans, "classified but not declared in Result::CATEGORIES: #{orphans.inspect}"
  end

  # :unknown is what Result.err defaults to, so it means "nobody said".
  # Answering either question for it would be an invention.
  def test_unknown_is_deliberately_unclassified
    unknown = err(:unknown)

    refute unknown.retriable?
    refute unknown.permanent?
    refute unknown.classified?
    refute_includes R::CATEGORIES.keys, :unknown, "if :unknown becomes declared, it needs a side"
  end

  # --- the classifications themselves -------------------------------------

  # The one that made the gap worth closing rather than recording.
  def test_a_rate_limit_is_retriable
    assert err(:rate_limit).retriable?, "a rate limit is the one failure that is retriable by definition"
    refute err(:rate_limit).permanent?
  end

  def test_environment_failures_are_retriable
    %i[infrastructure timeout provider_error llm_failure llm_call_failure].each do |category|
      assert err(category).retriable?, "#{category} is a failure of the environment, not of the request"
    end
  end

  def test_a_rejected_request_is_permanent
    %i[validation axiom_violation policy].each do |category|
      assert err(category).permanent?, "#{category} reproduces on every retry"
    end
  end

  def test_a_missing_key_is_not_something_to_retry_against
    assert err(:no_api_key).permanent?, "retrying a missing credential burns the retry budget on nothing"
  end

  def test_a_spent_budget_is_permanent
    assert err(:budget).permanent?, "the whole point of a budget is that trying again does not restore it"
  end

  def test_the_operation_being_over_is_permanent
    %i[shutdown abort].each { |category| assert err(category).permanent? }
  end

  # --- Err's own contract -------------------------------------------------

  def test_an_undeclared_category_is_refused_at_construction
    assert_raises(ArgumentError) { R.err("boom", category: :not_a_category) }
  end

  def test_a_nil_message_is_refused
    assert_raises(ArgumentError) { R::Err.new(nil) }
  end

  def test_a_non_symbol_category_is_refused
    assert_raises(ArgumentError) { R::Err.new("boom", "timeout") }
  end

  def test_an_error_carries_where_it_came_from
    context = R.err("boom", category: :timeout).context

    assert_equal "boom", context[:attempted]
    assert_includes context[:file].to_s, "test_err_classification"
    refute_nil context[:method]
  end

  def test_extra_context_merges_rather_than_replacing
    context = R.err("boom", category: :timeout, context: { host: "vm23" }).context

    assert_equal "vm23", context[:host]
    assert_equal "boom", context[:attempted], "caller context overwrote the error's own record"
  end

  def test_non_hash_context_is_carried_rather_than_dropped
    assert_equal 42, R.err("boom", category: :timeout, context: 42).context[:detail]
  end

  # --- chaining -----------------------------------------------------------

  # An Err short-circuits the chain: all three are identity no-ops, and the
  # block must not run.
  def test_an_error_short_circuits_every_combinator
    failure = err(:timeout)
    ran = false

    assert_same failure, failure.map { ran = true }
    assert_same failure, failure.flat_map { ran = true }
    assert_same failure, failure.and_then { ran = true }
    refute ran, "a combinator ran its block against a failure"
  end

  def test_an_ok_carries_the_chain
    doubled = R.ok(2).map { |value| value * 2 }

    assert doubled.ok?
    assert_equal 4, doubled.value!
  end

  def test_a_chain_that_fails_partway_keeps_the_first_failure
    first = err(:validation)
    result = R.ok(1).flat_map { first }.map { |v| v * 100 }

    assert_same first, result
    assert_equal :validation, result.category
  end

  # --- the constructors ---------------------------------------------------

  def test_from_turns_a_nil_into_a_named_failure
    result = R.from(nil, err_msg: "nothing there", category: :validation)

    assert result.err?
    assert_equal "nothing there", result.message
    assert_equal :validation, result.category
  end

  def test_from_passes_a_present_value_through
    assert_equal 0, R.from(0, err_msg: "x").value!, "zero and false are values, not absences"
    assert R.from(false, err_msg: "x").ok?
  end

  def test_wrap_leaves_a_result_alone_and_lifts_anything_else
    already = R.ok(1)

    assert_same already, R.wrap(already)
    assert_equal 5, R.wrap(5).value!
  end

  def test_an_ok_is_frozen_so_a_reader_cannot_rewrite_it
    assert R.ok(1).frozen?
  end
end
