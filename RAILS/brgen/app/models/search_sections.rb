# frozen_string_literal: true

# The global search page's sections: each vertical's first rows, only the
# verticals that found something, and each one's full total.
class SearchSections
  SIZE = 8

  Section = Data.define(:vertical, :records, :rows) do
    # A short section is its own count; a full one is counted once more.
    def total = rows.size < SIZE ? rows.size : records.count
  end

  def self.from(results)
    results.filter_map do |vertical, records|
      rows = records.limit(SIZE).to_a
      Section.new(vertical:, records:, rows:) if rows.any?
    end
  end
end
