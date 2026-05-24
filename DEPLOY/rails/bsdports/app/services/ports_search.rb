# frozen_string_literal: true

class PortsSearch
  COLUMNS = %w[name summary description].freeze

  def self.call(query:, scope: Port.all)
    new(query:, scope:).call
  end

  def initialize(query:, scope:)
    @query = query.to_s.strip
    @scope = scope
  end

  def call
    return scope.order(:name) if query.empty?

    if defined?(Shared::LiveSearch)
      Shared::LiveSearch.call(scope, query:, columns: COLUMNS).order(:name)
    else
      like = "%#{ActiveRecord::Base.sanitize_sql_like(query)}%"
      scope.where("name LIKE :q OR summary LIKE :q OR description LIKE :q", q: like).order(:name)
    end
  end

  private

  attr_reader :query, :scope
end
