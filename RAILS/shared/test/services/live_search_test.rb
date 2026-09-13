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
  # A real SQLite relation, because the defect was in the SQL: sanitize_sql_like
  # escapes % with a backslash and SQLite ignores that without an ESCAPE clause.
  def test_a_percent_sign_in_the_query_is_literal_on_sqlite
    require "sqlite3"
    ActiveRecord::Base.establish_connection(adapter: "sqlite3", database: ":memory:")
    ActiveRecord::Base.connection.create_table(:live_search_items) { |t| t.string :title }
    model = Class.new(ActiveRecord::Base) { self.table_name = "live_search_items" }
    model.create!(title: "100% ull")
    model.create!(title: "1000 ting")

    found = Shared::LiveSearch.search(model.all, query: "100%", columns: %w[title], app: "test").scope.pluck(:title)

    assert_equal [ "100% ull" ], found
  end

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
