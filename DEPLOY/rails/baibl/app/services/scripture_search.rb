# frozen_string_literal: true

class ScriptureSearch
  COLUMNS = %w[text reference book_name].freeze

  def self.call(query:, scope: Verse.all)
    new(query:, scope:).call
  end

  def initialize(query:, scope:)
    @query = query.to_s.strip
    @scope = scope
  end

  def call
    return scope.order(:book_index, :chapter, :number) if query.empty?

    if defined?(Shared::LiveSearch)
      Shared::LiveSearch.call(scope, query:, columns: COLUMNS).order(:book_index, :chapter, :number)
    else
      like = "%#{ActiveRecord::Base.sanitize_sql_like(query)}%"
      scope.where("text LIKE :q OR reference LIKE :q OR book_name LIKE :q", q: like).order(:book_index, :chapter, :number)
    end
  end

  private

  attr_reader :query, :scope
end
