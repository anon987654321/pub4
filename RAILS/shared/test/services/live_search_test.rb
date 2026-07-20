# frozen_string_literal: true

require "minitest/autorun"
require "active_record"
require "active_support/core_ext/string/filters"
require_relative "../../app/services/shared/live_search"

unless defined?(Rails)
  module Shared
    class EventEmitter
      def self.call(*) = nil
    end
  end
end

class SharedLiveSearchTest < Minitest::Test
  def test_empty_query_returns_original_scope
    scope = Object.new
    result = Shared::LiveSearch.search(scope, query: "", columns: %w[title])
    assert_equal scope, result.scope
    assert_equal 0, result.result_count
  end

  def test_related_terms_on_zero_results
    connection = Class.new do
      def data_source_exists?(_) = false
      def adapter_name = "SQLite"
    end.new
    model = Class.new do
      define_singleton_method(:table_name) { "items" }
      define_singleton_method(:search) { |_| none }
      define_singleton_method(:none) { self.relation }
      define_singleton_method(:connection) { connection }

      define_singleton_method(:relation) do
        relation = Object.new
        relation.define_singleton_method(:klass) { model }
        relation.define_singleton_method(:connection) { connection }
        relation.define_singleton_method(:merge) { |_| self }
        relation.define_singleton_method(:where) { |*| self }
        relation.define_singleton_method(:limit) { |_| self }
        relation.define_singleton_method(:count) { 0 }
        relation
      end
    end
    scope = model.relation

    result = Shared::LiveSearch.search(scope, query: "bicycles", columns: %w[title], vertical: "test", app: "test")
    assert_equal 0, result.result_count
    assert_includes result.suggestions, "bicycles"
  end
end
