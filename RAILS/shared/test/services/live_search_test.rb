# frozen_string_literal: true

require "minitest/autorun"
require "minitest/mock"
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

  # A deal is found by its listing's title, so a table-qualified column must
  # reach the joined table instead of being prefixed with the scope's own.
  def test_a_qualified_column_searches_the_joined_table
    require "sqlite3"
    ActiveRecord::Base.establish_connection(adapter: "sqlite3", database: ":memory:")
    connection = ActiveRecord::Base.connection
    connection.create_table(:live_search_parents) { |t| t.string :title }
    connection.create_table(:live_search_children) { |t| t.string :headline; t.integer :live_search_parent_id }
    parent = Class.new(ActiveRecord::Base) { self.table_name = "live_search_parents" }
    child = Class.new(ActiveRecord::Base) { self.table_name = "live_search_children" }
    bike = parent.create!(title: "Racersykkel")
    child.create!(headline: "Vårsalg", live_search_parent_id: bike.id)
    child.create!(headline: "Sofa", live_search_parent_id: parent.create!(title: "Stue").id)

    scope = child.joins("JOIN live_search_parents ON live_search_parents.id = live_search_children.live_search_parent_id")
    found = Shared::LiveSearch.search(scope, query: "racer", columns: %w[headline live_search_parents.title], app: "test").scope

    assert_equal [ "Vårsalg" ], found.pluck(:headline)
  end

  def test_call_filters_without_counting_or_reporting
    scope = Object.new
    def scope.where(*) = :filtered
    reported = []
    Shared::EventEmitter.stub(:call, ->(*args, **kw) { reported << [ args, kw ] }) do
      model = Class.new { def self.table_name = "items" }
      scope.define_singleton_method(:klass) { model }
      scope.define_singleton_method(:connection) { raise "no fts probe needed" }
      assert_equal :filtered, Shared::LiveSearch.call(scope, query: "sykkel", columns: %w[title])
    end
    assert_empty reported, "a filter on a reader's behalf is not a search they typed"
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
