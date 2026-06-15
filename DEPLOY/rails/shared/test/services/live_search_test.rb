# frozen_string_literal: true

require "minitest/autorun"
require "active_record"
require "active_support/core_ext/string/filters"
require_relative "../../app/services/shared/live_search"

class SharedLiveSearchTest < Minitest::Test
  def test_empty_query_returns_original_scope
    scope = Object.new
    result = Shared::LiveSearch.search(scope, query: "", columns: %w[title])
    assert_equal scope, result.scope
    assert_equal 0, result.result_count
  end

  def test_related_terms_on_zero_results
    scope = Class.new do
      def self.table_name = "items"
      def self.search(_) = none
      def self.none = self
      def self.merge(_) = self
      def self.connection = @connection ||= Connection.new
      def self.where(*) = self
      def self.limit(_) = self
      def self.count = 0

      class Connection
        def data_source_exists?(_) = false
        def adapter_name = "SQLite"
      end
    end

    result = Shared::LiveSearch.search(scope, query: "bicycles", columns: %w[title], vertical: "test", app: "test")
    assert_equal 0, result.result_count
    assert_includes result.suggestions, "bicycles"
  end
end