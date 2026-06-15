# frozen_string_literal: true

class ScriptureSearch
  COLUMNS = %w[content].freeze

  def self.call(query:, scope: Verse.all)
    Shared::LiveSearch.search(scope, query:, columns: COLUMNS, vertical: "scripture", app: "baibl").scope
                       .includes(:book, :chapter)
                       .order(:book_id, :chapter_id, :number)
  end
end