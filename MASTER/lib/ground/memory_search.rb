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

        docs.values.map do |doc|
          score = score_doc(doc, terms)
          next if score <= 0

          doc.merge("score" => score)
        end.compact.sort_by { |doc| -doc["score"] }.first(limit)
      end

      def brief(query, limit: 5)
        rows = search(query, limit:)
        return "Memory search: no hits for #{query.inspect}." if rows.empty?

        lines = rows.map { |doc| "- #{doc['path']} score=#{format('%.2f', doc['score'])} title=#{doc['title']}" }
        "Memory search hits:\n#{lines.join("\n")}"
      end

      private

      def score_doc(doc, terms)
        counts = doc.fetch("terms", {})
        terms.sum { |term| Math.log(1 + counts.fetch(term, 0).to_f) }
      end
    end
  end
end
