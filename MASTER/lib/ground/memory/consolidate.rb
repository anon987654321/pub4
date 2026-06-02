# frozen_string_literal: true

module Master
  module Ground
    class Memory
      module Consolidate
        def context_summary
          active = active_entries
          return if active.empty?

          lines = summary_lines(active)
          return if lines.empty?

          header = summary_header
          "#{header}\n#{lines.join("\n")}"
        end

        def consolidate!(agent: nil)
          return "nothing to consolidate" if @store.empty?

          entries, archived = archive_old_entries(Time.now.to_i)
          summarize_active_entries(agent) if agent
          "dreaming: #{entries.size} entries checked, #{archived} archived"
        rescue StandardError => e
          "consolidation error: #{e.message}"
        end

        private

        def active_entries
          @mutex.synchronize do
            @store.reject { |key, _| key.to_s.start_with?("archive/") || key == "_consolidated_summary" }
          end
        end

        def summary_lines(active)
          lines = []
          token_sum = 0
          current_type = nil
          ordered_entries(active).each do |key, value|
            type = entry_type(value)
            lines << "[#{type}]" if type != current_type
            current_type = type
            text = "- #{key}: #{entry_value(value)}"
            estimated_tokens = text.bytesize / Master::Trace::Session::TOKENS_PER_CHAR
            break if token_sum + estimated_tokens > MAX_INJECT_TOKENS

            lines << text
            token_sum += estimated_tokens
          end
          lines
        end

        def ordered_entries(active)
          grouped = active.group_by { |_, value| entry_type(value) }
          TYPES.flat_map do |type|
            (grouped[type] || []).sort_by { |_, value| -entry_timestamp(value) }
          end.first(MAX_INJECT_ENTRIES * 2)
        end

        def summary_header
          summary = recall("_consolidated_summary")
          header = summary ? "Memory (#{summary.to_s[0, 80]}):" : "Memory:"
          archived_n = @mutex.synchronize { @store.count { |key, _| key.to_s.start_with?("archive/") } }
          archived_n.positive? ? "#{header} [+#{archived_n} archived]" : header
        end

        def archive_old_entries(now)
          archived = 0
          entries = nil
          @mutex.synchronize do
            entries = @store.reject { |key, _| key.to_s.start_with?("archive/") }
            scored_entries(entries, now).each do |entry|
              next if entry[:key] == "_consolidated_summary"
              next unless entry[:score] < 0.33

              @store["archive/#{entry[:key]}"] = @store.delete(entry[:key])
              archived += 1
            end
            persist
          end
          [entries, archived]
        end

        def scored_entries(entries, now)
          entries.map do |key, data|
            age_days = (now - entry_timestamp(data)) / 86_400.0
            { key: key, score: 1.0 / (1.0 + age_days / TTL_DAYS.to_f) }
          end
        end

        def summarize_active_entries(agent)
          active_text = active_entries.map { |key, value| "#{key}: #{entry_value(value)}" }.join("\n")
          return if active_text.strip.empty?

          summary = agent.ask_once("Summarize in 2 concise sentences, preserving all key facts:\n#{active_text}")
          remember("_consolidated_summary", summary.strip)
        end

        def entry_type(value)
          value.is_a?(Hash) ? (value["type"] || "general") : "general"
        end

        def entry_value(value)
          value.is_a?(Hash) ? value["value"] : value
        end

        def entry_timestamp(value)
          value.is_a?(Hash) ? value["ts"].to_i : 0
        end
      end
    end
  end
end
