# frozen_string_literal: true

module Master
  module Ground
    class Memory
      module Search
        def semantic_recall(query, top_n: 3)
          store_snap = @mutex.synchronize { @store.dup }
          return [] if store_snap.empty?

          if Judge::Embeddings.enabled? && (qvec = Judge::Embeddings.embed(query))
            hits = vector_recall(qvec, top_n, store_snap)
            return hits unless hits.empty?

          tfidf_recall(query, top_n, store_snap)
        end

        private

        def vector_recall(qvec, top_n, store)
          store.filter_map do |key, data|
            next unless data.is_a?(Hash) && data["vec"].is_a?(Array)

            score = Judge::Embeddings.cosine(qvec, data["vec"])
            next if score < Judge::Embeddings::MIN_SIM

            { key: key, value: data["value"].to_s, score: score }
          end.sort_by { |e| -e[:score] }.first(top_n)
        end

        def tfidf_recall(query, top_n, store)
          terms = tokenize(query)
          return [] if terms.empty?

          store.filter_map do |key, data|
            value = data.is_a?(Hash) ? data["value"].to_s : data.to_s
            score = tfidf_score(terms, tokenize("#{key} #{value}"))
            next if score.zero?

            { key: key, value: value, score: score }
          end.sort_by { |e| -e[:score] }.first(top_n)
        end

        def tokenize(text) = text.downcase.scan(/\b[a-z]{2,}\b/)

        def tfidf_score(query_terms, doc_terms)
          return 0.0 if doc_terms.empty?

          freq = doc_terms.tally
          query_terms.sum { |t| Math.log(1.0 + freq.fetch(t, 0).to_f) }
        end
      end
    end
  end
end
