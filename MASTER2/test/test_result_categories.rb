# frozen_string_literal: true

require "minitest/autorun"
require_relative "../lib/result"

module MASTER
  class TestResultCategories < Minitest::Test
    def test_categories_constant_defined
      assert_equal %i[infrastructure validation timeout budget axiom_violation unknown], Result::CATEGORIES
    end

    def test_ok_result_has_no_category_predicates
      r = Result.ok("value")
      refute r.retriable?
      refute r.permanent?
      refute r.infrastructure?
    end

    def test_err_default_category_is_unknown
      r = Result.err("oops")
      assert_equal :unknown, r.category
      refute r.retriable?
      refute r.permanent?
    end

    def test_infrastructure_category
      r = Result.err("network down", category: :infrastructure)
      assert_equal :infrastructure, r.category
      assert r.retriable?
      assert r.infrastructure?
      refute r.permanent?
    end

    def test_timeout_category_is_retriable
      r = Result.err("timed out", category: :timeout)
      assert r.retriable?
      refute r.permanent?
      refute r.infrastructure?
    end

    def test_validation_category_is_permanent
      r = Result.err("bad input", category: :validation)
      assert r.permanent?
      refute r.retriable?
    end

    def test_axiom_violation_category_is_permanent
      r = Result.err("violated axiom", category: :axiom_violation)
      assert r.permanent?
      refute r.retriable?
    end

    def test_budget_category_is_permanent
      r = Result.err("budget exceeded", category: :budget)
      assert r.permanent?
      refute r.retriable?
    end

    def test_metadata_stored_and_frozen
      r = Result.err("fail", category: :infrastructure, metadata: { model: "gpt-4", attempt: 1 })
      assert_equal "gpt-4", r.metadata[:model]
      assert r.metadata.frozen?
    end

    def test_ok_result_has_unknown_category_and_empty_metadata
      r = Result.ok(42)
      assert_equal :unknown, r.category
      assert_equal({}, r.metadata)
    end

    def test_result_is_frozen
      r = Result.err("frozen", category: :validation)
      assert r.frozen?
    end
  end
end
