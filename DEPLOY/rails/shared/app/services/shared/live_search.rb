# frozen_string_literal: true

module Shared
  class LiveSearch
    Result = Data.define(:scope, :result_count, :latency_ms, :suggestions)

    def self.search(scope, query:, columns:, vertical: nil, app: nil)
      new(scope, query:, columns:, vertical:, app:).search
    end

    def self.call(scope, query:, columns:)
      search(scope, query:, columns:).scope
    end

    def initialize(scope, query:, columns:, vertical: nil, app: nil)
      @scope = scope
      @query = query.to_s.strip
      @columns = Array(columns)
      @vertical = vertical
      @app = app
    end

    def search
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      filtered = filtered_scope
      count = safe_count(filtered)
      latency_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round
      notify_analytics(count, latency_ms)
      suggestions = count.zero? && query.present? ? related_terms : []
      Result.new(scope: filtered, result_count: count, latency_ms: latency_ms, suggestions: suggestions)
    end

    private

    attr_reader :scope, :query, :columns, :vertical, :app

    def filtered_scope
      return scope if query.blank? || columns.empty?

      if fts_scope?
        begin
          return scope.merge(scope.klass.search(query))
        rescue StandardError => e
          Rails.logger.warn("live_search fts fallback: #{e.message}")
        end
      end

      like = "%#{ActiveRecord::Base.sanitize_sql_like(query)}%"
      operator = sqlite? ? "LIKE" : "ILIKE"
      table = scope.klass.table_name
      predicate = columns.map { |column| "#{table}.#{column} #{operator} :query" }.join(" OR ")
      scope.where(predicate, query: like)
    end

    def fts_scope?
      scope.klass.respond_to?(:search) &&
        scope.connection.data_source_exists?("#{scope.klass.table_name}_fts")
    rescue StandardError
      false
    end

    def safe_count(filtered)
      return 0 if filtered.null_relation?

      filtered.limit(500).count
    end

    def notify_analytics(count, latency_ms)
      return if query.blank?

      payload = {
        query: query,
        result_count: count,
        latency_ms: latency_ms,
        vertical: vertical,
        app: app_name
      }
      Shared::EventEmitter.call("search.query", **payload)
    end

    def related_terms
      tokens = query.downcase.split(/\W+/).reject { |token| token.length < 3 }
      tokens.flat_map { |token| [token, token.chop, "#{token}s"] }.uniq.first(5)
    end

    def app_name
      app.presence || Rails.application.class.module_parent_name.to_s.downcase
    end

    def sqlite?
      ActiveRecord::Base.connection.adapter_name.downcase.include?("sqlite")
    end
  end
end