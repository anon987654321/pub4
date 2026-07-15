# frozen_string_literal: true

module Master
  module Judge
    class RepoEcology
      # Converts a computed scan report hash into markdown text — a separate
      # concern from RepoEcology's own file-analysis/detection responsibility.
      module ReportRendering
        def build_scan_report(records, graph)
          {
            root: @root,
            scanned_at: Time.now.utc.iso8601,
            files: records.size,
            score: score(records),
            dead_file_candidates: dead_file_candidates(records),
            dead_method_candidates: dead_method_candidates(records),
            duplicate_basenames: duplicate_basenames(records),
            similar_clusters: similar_clusters(records),
            sprawl: sprawl(records),
            large_files: large_files(records),
            extension_mix: extension_mix(records),
            co_change_pairs: co_change_pairs(graph)
          }
        end

        def render_report_sections(report)
          render_dead_and_duplicate_sections(report) + render_scale_and_coupling_sections(report)
        end

        def render_dead_and_duplicate_sections(report)
          lines = []
          lines.concat(render_section("Dead-file candidates", report[:dead_file_candidates]) do |item|
            "#{item[:path]} — #{item[:reason]}"
          end)
          lines.concat(render_section("Dead-method candidates", report[:dead_method_candidates]) do |item|
            "#{item[:path]}##{item[:method]} — #{item[:reason]}"
          end)
          lines.concat(render_section("Duplicate basenames", report[:duplicate_basenames]) do |item|
            "#{item[:basename]} ×#{item[:count]}: #{item[:paths].first(5).join(', ')}"
          end)
          lines
        end

        def render_scale_and_coupling_sections(report)
          lines = []
          lines.concat(render_section("Similar clusters", report[:similar_clusters]) do |item|
            "#{item[:signature]} ×#{item[:count]}: #{item[:paths].first(5).join(', ')}"
          end)
          lines.concat(render_section("Large files", report[:large_files]) do |item|
            "#{item[:path]} — #{item[:lines]} lines (#{item[:symbol_count]} symbols)"
          end)
          lines.concat(render_section("Co-change pairs (hidden coupling)", report[:co_change_pairs]) do |item|
            "#{item[:a]} ↔ #{item[:b]} (#{item[:count]} commits)"
          end)
          lines
        end

        def render_summary_lines(report)
          sprawl = report[:sprawl]
          [
            "sprawl: max_depth=#{sprawl[:max_depth]}, avg_depth=#{sprawl[:avg_depth]}, " \
            "orphan_dirs=#{sprawl[:orphan_dirs]}",
            "extensions: #{report[:extension_mix].map { |ext, count| "#{ext}=#{count}" }.join(', ')}",
          ]
        end

        def render_section(title, items)
          lines = ["", "## #{title}"]
          if items.empty?
            lines << "none"
          else
            items.first(12).each { |item| lines << "- #{yield(item)}" }
          end
          lines
        end
      end
    end
  end
end
