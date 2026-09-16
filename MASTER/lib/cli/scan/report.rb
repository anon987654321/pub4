# frozen_string_literal: true

require_relative "../../fix/conflict_resolver"

module Master
  module CLI
    module Scan
      class Report
        def initialize(pairs:, profile:, rule_filter:, severity_filter: nil, dry_run: false, autofixes: [],
                       phase: nil, prior_total: nil)
          @pairs = pairs
          @profile = profile
          @rule_filter = rule_filter
          @severity_filter = severity_filter
          @dry_run = dry_run
          @autofixes = Array(autofixes)
          @phase = phase
          @prior_total = prior_total
          @conflicts = Master::Fix::ConflictResolver.new(root: Master::ROOT)
        end

        def render
          return render_clean if total.zero?

          lines = []
          lines << phase_line if phase_line
          lines << "#{prefix}#{header}#{total} total violations#{suffix}"
          lines << delta_line if delta_line
          lines << autofix_line if autofix_line
          cross_file_line = cross_file_drifts_line
          lines << cross_file_line if cross_file_line
          ranked.first(CommandRegistry::SCAN_RULE_GROUP_LIMIT).each do |rule, violations|
            lines << "#{rule} #{violations.size}"
            lines.concat(violations.first(3).map { |violation| violation_line(violation) })
          end
          lines << omitted_line if omitted_count.positive?
          lines.join("\n")
        end

        # Compact one-screen summary for checkpoints / interrupt dumps / pass1.
        # One dmesg line: "12 violations; top LONG_LINE 5, DEAD_CODE 2".
        def brief
          top = ranked.first(8).map { |rule, vs| "#{rule} #{vs.size}" }.join(", ")
          parts = [total.zero? ? "#{prefix}#{header}clean#{suffix}" : "#{prefix}#{header}#{total} violations"]
          parts << "top #{top}" unless top.empty?
          parts << autofix_line
          parts << delta_line
          parts.compact.join("; ")
        end

        def total_count
          total
        end

        private

        attr_reader :pairs, :profile, :rule_filter, :severity_filter, :dry_run, :autofixes, :conflicts,
                    :phase, :prior_total

        def render_clean
          lines = []
          lines << phase_line if phase_line
          lines << "#{prefix}#{header}clean -- no violations#{suffix}"
          lines << delta_line if delta_line
          lines << autofix_line if autofix_line
          lines.join("\n")
        end

        def phase_line
          return unless phase

          "phase: #{phase}"
        end

        def delta_line
          return if prior_total.nil?

          delta = total - prior_total.to_i
          sign = delta.positive? ? "+" : ""
          "delta: #{prior_total} → #{total} (#{sign}#{delta})"
        end

        def autofix_line
          return if autofixes.empty?

          transforms = autofixes.flat_map { |item| autofix_transforms(item) }.uniq
          detail = transforms.empty? ? "" : " (#{transforms.first(6).join(", ")})"
          "autofixed: #{autofixes.size} file#{'s' unless autofixes.size == 1}#{detail}"
        end

        def autofix_transforms(item)
          return Array(item[:transforms]) if item.respond_to?(:[]) && item[:transforms]
          return Array(item.transforms) if item.respond_to?(:transforms)

          []
        end

        def by_rule
          @by_rule ||= clustered_violations.each_with_object(Hash.new { |h, k| h[k] = [] }) do |violation, groups|
              next if rule_filter && !rule_filter.include?(violation[:rule].to_s)
              next if severity_filter && !severity_filter.include?(violation[:severity].to_s)

              # Canonical RuleDSL ids are uppercase, but some findings carry a
              # lowercase label (e.g. principle_map.yml's "detects:" taxonomy)
              # for the same category -- normalize so it doesn't split into a
              # second entry (see Scanner::ProgressReporter for the same fix).
              groups[violation[:rule].to_s.upcase] << violation
          end
        end

        def filtered_violations
          conflicts.filter_findings(raw_violations).map { |finding| symbolize_keys(finding) }
        end

        def clustered_violations
          @clustered_violations ||= filtered_violations.group_by { |violation| violation.fetch(:dedupe_key) { default_dedupe_key(violation) } }.map do |_, cluster|
            confidences = cluster.map { |v| v[:confidence].to_f }.reject(&:zero?)
            cluster.first.merge(
              count: cluster.size,
              files: cluster.map { |v| v[:file] }.compact.uniq,
              lines: cluster.map { |v| v[:line] }.compact.uniq.sort,
              confidence: confidences.empty? ? cluster.first[:confidence] : confidences.sum / confidences.size.to_f,
              impact_radius: impact_radius(cluster),
              why: cluster.first.fetch(:why) { default_why(cluster.first) },
              genealogy: cluster.first.fetch(:genealogy) { default_genealogy(cluster.first) },
            )
          end
        end

        def raw_violations
          pairs.flat_map do |(file, file_result)|
            Result.wrap(file_result).value_or([]).map { |violation| violation.merge(file:) }
          end
        end

        def symbolize_keys(finding)
          finding.each_with_object({}) { |(key, value), out| out[key.to_sym] = value }
        end

        def total
          @total ||= by_rule.values.sum(&:size)
        end

        # Blast radius, not firing count: an error across five files outranks an
        # info across five hundred. impact_radius was computed already, for display.
        def ranked
          @ranked ||= by_rule.sort_by do |rule, v|
            radius = impact_radius(v)
            [-(radius[:files_affected] * radius[:severity_multiplier]), -v.size, rule]
          end
        end

        # "  web/public/face.css:28 raw hex color — use a design token, 14 files".
        # The place and the message. Confidence, a why that restated the
        # message, a genealogy that restated the rule and an impact tuple made
        # each line a pipe-separated dump no one read.
        def violation_line(violation)
          place = [violation[:file].to_s.delete_prefix("#{Master::ROOT}/"), violation[:line]].reject { |p| p.to_s.empty? }.join(":")
          files = Array(violation[:files]).size
          "  #{place} #{clipped(violation[:message])}#{", #{files} files" if files > 1}"
        end

        # A hard slice cut mid-word and said nothing about it: an adversarial
        # finding ended "contradicting the commen", which reads as a typo in the
        # finding rather than the end of the room for it. Cut at the last space
        # and say so.
        def clipped(message, limit: CommandRegistry::VIOLATION_TRUNCATE)
          text = message.to_s
          return text if text.length <= limit

          head = text[0, limit]
          space = head.rindex(" ")
          "#{(space && space > limit / 2 ? head[0, space] : head).rstrip}…"
        end

        def omitted_count
          ranked.drop(CommandRegistry::SCAN_RULE_GROUP_LIMIT).sum { |_, violations| violations.size }
        end

        def omitted_line
          "#{omitted_count} more #{omitted_count == 1 ? 'violation' : 'violations'} omitted"
        end

        def cross_file_drifts_line
          clusters = cross_file_duplicate_clusters
          return if clusters.empty?

          summary = clusters.first(3).map do |cluster|
            "#{cluster[:rule]}×#{cluster[:count]}#{cluster[:files] > 1 ? " in #{cluster[:files]} files" : ""}"
          end.join(" ")
          "cross-file DRY: #{summary}"
        end

        def impact_radius(cluster)
          {
            files_affected: Array(cluster.map { |v| v[:file] }.compact.uniq).size,
            occurrences: cluster.size,
            severity_multiplier: severity_multiplier(cluster.first[:severity]),
          }
        end

        def severity_multiplier(severity)
          case severity.to_s
          when "error" then 1.5
          when "warning" then 1.0
          else 0.75
          end
        end

        def default_dedupe_key(violation)
          "#{violation[:rule]}:#{violation[:message].to_s.downcase.gsub(/\b\d+\b/, "#")}"
        end

        def default_why(violation)
          "#{violation[:message]} because repeated occurrences amplify maintenance risk."
        end

        def default_genealogy(violation)
          [violation[:severity].to_s.upcase, violation[:rule].to_s, violation[:message].to_s.split(" — ").first]
        end

        def cross_file_duplicate_clusters
          by_signature = clustered_violations.group_by do |violation|
            [violation[:rule].to_s, violation[:message].to_s.downcase, violation[:fix].to_s.downcase]
          end

          by_signature.filter_map do |(rule, message, fix), cluster|
            files = Array(cluster.map { |v| v[:file] }.compact.uniq)
            next if files.size < 2 && cluster.size < 3

            {
              rule:,
              message:,
              fix:,
              count: cluster.size,
              files: files.size,
            }
          end.sort_by { |cluster| [-cluster[:count], -cluster[:files], cluster[:rule]] }
        end

        def header
          profile ? "[profile: #{profile}] " : ""
        end

        def prefix
          dry_run ? "dry-run: " : ""
        end

        def suffix
          dry_run ? " (no changes made)" : ""
        end
      end
    end
  end
end
