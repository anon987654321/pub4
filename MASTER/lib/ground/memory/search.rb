# frozen_string_literal: true

begin
  require "sqlite3"
rescue LoadError
  nil
end

module Master
  module Ground
    class Memory
      module Search
        RRF_K = 60.0

        def semantic_recall(query, top_n: 3)
          hybrid_recall(query, top_n: top_n)
        end

        def hybrid_recall(query, top_n: 3)
          store_snap = @mutex.synchronize { @store.dup }
          return [] if store_snap.empty?

          return fts5_recall_from_store(query: query, top_n: top_n, store: store_snap) if fts5_only?

          keyword_hits = keyword_hits(query: query, top_n: top_n * 3, store: store_snap)
          vector_hits = []
          if Judge::Embeddings.enabled? && (qvec = Judge::Embeddings.embed(query))
            vector_hits = vector_recall(qvec: qvec, top_n: top_n * 3, store: store_snap)
          end

          fused = rrf(keyword_hits, vector_hits)
          fused.empty? ? keyword_hits.first(top_n) : fused.first(top_n)
        end

        def keyword_recall(query, top_n: 3)
          store_snap = @mutex.synchronize { @store.dup }
          keyword_hits(query: query, top_n: top_n, store: store_snap)
        end

        def fts5_recall(query, top_n: 3)
          store_snap = @mutex.synchronize { @store.dup }
          fts5_recall_from_store(query: query, top_n: top_n, store: store_snap)
        end

        private

        def keyword_hits(query:, top_n:, store:)
          return fts5_recall_from_store(query: query, top_n: top_n, store: store) if fts5_available?

          tfidf_recall(query: query, top_n: top_n, store: store)
        end

        def fts5_only?
          ENV["MASTER_MEMORY_SEARCH"].to_s == "fts5" || ENV["MASTER_ZERO_EMBEDDINGS"].to_s == "1"
        end

        def fts5_available?
          defined?(SQLite3::Database)
        end

        def vector_recall(qvec:, top_n:, store:)
          store.filter_map do |key, data|
            next unless data.is_a?(Hash) && data["vec"].is_a?(Array)

            score = Judge::Embeddings.cosine(qvec, data["vec"])
            next if score < Judge::Embeddings::MIN_SIM

            { key: key, value: data["value"].to_s, score: score }
          end.sort_by { |e| -e[:score] }.first(top_n)
        end

        def tfidf_recall(query:, top_n:, store:)
          terms = tokenize(query)
          return [] if terms.empty?

          store.filter_map do |key, data|
            value = data.is_a?(Hash) ? data["value"].to_s : data.to_s
            score = tfidf_score(terms, tokenize("#{key} #{value}"))
            next if score.zero?

            { key: key, value: value, score: score }
          end.sort_by { |e| -e[:score] }.first(top_n)
        end

        def fts5_recall_from_store(query:, top_n:, store:)
          terms = tokenize(query).uniq
          return [] if terms.empty?
          return tfidf_recall(query: query, top_n: top_n, store: store) unless fts5_available?

          db = SQLite3::Database.new(":memory:")
          db.results_as_hash = true
          db.execute_batch(<<~SQL)
            CREATE VIRTUAL TABLE memory_fts USING fts5(
              key UNINDEXED,
              value,
              tokenize = 'porter'
            );
          SQL
          store.each do |key, data|
            value = data.is_a?(Hash) ? data["value"].to_s : data.to_s
            db.execute("INSERT INTO memory_fts(key, value) VALUES (?, ?)", [key.to_s, value])
          end

          db.execute(<<~SQL, [fts5_query(terms), top_n]).map do |row|
            SELECT key, value, bm25(memory_fts) AS rank
            FROM memory_fts
            WHERE memory_fts MATCH ?
            ORDER BY rank
            LIMIT ?
          SQL
            { key: row["key"], value: row["value"], score: -row["rank"].to_f, fusion: "fts5" }
          end
        rescue SQLite3::Exception
          tfidf_recall(query: query, top_n: top_n, store: store)
        ensure
          db&.close
        end

        def fts5_query(terms)
          terms.map { |term| "\"#{term.gsub("\"", "\"\"")}\"" }.join(" OR ")
        end

        def tokenize(text)
          text.downcase.scan(/\b[a-z]{2,}\b/)
        end

        def tfidf_score(query_terms, doc_terms)
          return 0.0 if doc_terms.empty?

          freq = doc_terms.tally
          query_terms.sum { |t| Math.log(1.0 + freq.fetch(t, 0).to_f) }
        end

        def rrf(*ranked_lists)
          scores = Hash.new(0.0)
          payloads = {}
          ranked_lists.each do |list|
            list.each_with_index do |hit, index|
              key = hit[:key]
              scores[key] += 1.0 / (RRF_K + index + 1)
              payloads[key] ||= hit
            end
          end
          scores.sort_by { |key, score| [-score, key.to_s] }.map do |key, score|
            payloads[key].merge(score: score, fusion: "rrf")
          end
        end
      end
    end
  end
end
