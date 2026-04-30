# frozen_string_literal: true

module Master
  class Memory
    module Search
      def semantic_recall(query, top_n: 3)
        return [] if @store.empty?

        query_terms = tokenize(query)
        return [] if query_terms.empty?

        scored = @store.filter_map do |key, data|
          value = data.is_a?(Hash) ? data["value"].to_s : data.to_s
          score = tfidf_score(query_terms, tokenize("#{key} #{value}"))
          next if score.zero?
          { key: key, value: value, score: score }
        end

        scored.sort_by { |e| -e[:score] }.first(top_n)
      end

      private

      def tokenize(text) = text.downcase.scan(/\b[a-z]{2,}\b/)

      def tfidf_score(query_terms, doc_terms)
        return 0.0 if doc_terms.empty?
        freq = doc_terms.tally
        query_terms.sum { |t| Math.log(1.0 + freq.fetch(t, 0).to_f) }
      end
    end
  end
end
