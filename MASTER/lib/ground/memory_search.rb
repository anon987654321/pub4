# frozen_string_literal: true

module Master
  module Ground
  class MemorySearch
    def initialize(index: MemoryIndex.new)
      @index = index
    end

    def search(query, limit: 8)
      docs = @index.load_index
      docs = @index.rebuild! if docs.empty?
      terms = query.to_s.downcase.scan(/[a-z0-9_\-]{3,}/)
      return [] if terms.empty?

      scored = docs.values.filter_map { |doc| score_or_skip(doc, terms) }
      scored.sort_by { |doc| -doc["score"] }.first(limit)
    end

    def score_or_skip(doc, terms)
      score = score_doc(doc, terms)
      score > 0 ? doc.merge("score" => score) : nil
    end

    def brief(query, limit: 5)
      rows = search(query, limit: limit)
      return "Memory search: no hits for #{query.inspect}." if rows.empty?

      "Memory search hits:\n" + rows.map { |doc| "- #{doc['path']} score=#{format('%.2f', doc['score'])} title=#{doc['title']}" }.join("\n")
    end

    private

    def score_doc(doc, terms)
      counts = doc.fetch("terms", {})
      terms.sum { |term| Math.log(1 + counts.fetch(term, 0).to_f) }
    end
  end
  end
end
