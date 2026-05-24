# frozen_string_literal: true

module Shared
  class LiveSearch
    def self.call(scope, query:, columns:)
      new(scope, query:, columns:).call
    end

    def initialize(scope, query:, columns:)
      @scope = scope
      @query = query.to_s.strip
      @columns = Array(columns)
    end

    def call
      return scope if query.empty? || columns.empty?

      like = "%#{ActiveRecord::Base.sanitize_sql_like(query)}%"
      operator = sqlite? ? "LIKE" : "ILIKE"
      predicate = columns.map { |column| "#{column} #{operator} :query" }.join(" OR ")
      scope.where(predicate, query: like)
    end

    private

    attr_reader :scope, :query, :columns

    def sqlite?
      ActiveRecord::Base.connection.adapter_name.downcase.include?("sqlite")
    end
  end
end
