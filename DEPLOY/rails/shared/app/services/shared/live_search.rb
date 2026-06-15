# frozen_string_literal: true

module Shared
  class LiveSearch
    Result = Data.define(:scope, :result_count, :latency_ms, :suggestions)

    def self.call(scope, query:, columns:, vertical: nil, filters: {}, actor: nil, locality: nil, app: nil)
      new(
        scope,
        query: query,
        columns: columns,
        vertical: vertical,
        filters: filters,
        actor: actor,
        locality: locality,
        app: app
      ).call.scope
    end

    def self.search(scope, query:, columns:, **options)
      new(scope, query: query, columns: columns, **options).call
    end

    def initialize(scope, query:, columns:, vertical: nil, filters: {}, actor: nil, locality: nil, app: nil)
      @scope = scope
      @query = query.to_s.strip
      @columns = Array(columns)
      @vertical = vertical
      @filters = filters || {}
      @actor = actor
      @locality = locality
      @app = app
    end

    def call
      return empty_result if query.empty? || columns.empty?

      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      results = fts_search(scope) || like_search(scope)
      count = result_count_for(results)
      latency_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round
      suggestions = count.zero? ? Shared::SearchSuggestions.for(query, vertical: vertical) : []

      Shared::SearchAnalytics.log(
        query: query,
        result_count: count,
        latency_ms: latency_ms,
        vertical: vertical,
        filters: filters,
        actor: actor,
        app: app,
        locality: locality
      )

      Result.new(scope: results, result_count: count, latency_ms: latency_ms, suggestions: suggestions)
    end

    private

    attr_reader :scope, :query, :columns, :vertical, :filters, :actor, :locality, :app

    def empty_result
      Result.new(scope: scope, result_count: 0, latency_ms: 0, suggestions: [])
    end

    def sqlite?
      ActiveRecord::Base.connection.adapter_name.downcase.include?("sqlite")
    end

    def fts_search(scope)
      return nil unless scope.respond_to?(:search)

      scope.search(query)
    rescue ActiveRecord::StatementInvalid, ArgumentError
      nil
    end

    def like_search(scope)
      like = "%#{ActiveRecord::Base.sanitize_sql_like(query)}%"
      operator = sqlite? ? "LIKE" : "ILIKE"
      predicate = columns.map { |column| "#{column} #{operator} :query" }.join(" OR ")
      scope.where(predicate, query: like)
    end

    def result_count_for(results)
      results.count(:all)
    rescue StandardError
      results.size
    end
  end
end