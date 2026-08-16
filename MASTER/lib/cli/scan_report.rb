# frozen_string_literal: true

require_relative "../fix/conflict_resolver"

module Master
  module CLI
    class ScanReport
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
        histogram_line = confidence_histogram_line
        lines << histogram_line if histogram_line
        lines << evidence_line
        cross_file_line = cross_file_drifts_line
        lines << cross_file_line if cross_file_line
        ranked.first(CommandRegistry::SCAN_RULE_GROUP_LIMIT).each do |rule, violations|
          lines << "[#{rule}]"
          lines.concat(violations.first(3).map { |violation| violation_line(violation) })
        end
        lines << omitted_line if omitted_count.positive?
        lines.join("\n")
      end

      # Compact one-screen summary for checkpoints / interrupt dumps / pass1.
      def brief
        if total.zero?
          parts = ["#{prefix}#{header}clean -- no violations#{suffix}"]
          parts << autofix_line if autofix_line
          parts << delta_line if delta_line
          return parts.compact.join(" | ")
        end

        top = ranked.first(8).map { |rule, vs| "#{rule}=#{vs.size}" }.join(" ")
        parts = ["#{prefix}#{header}#{total} violations"]
        parts << "top #{top}" unless top.empty?
        parts << autofix_line if autofix_line
        parts << delta_line if delta_line
        parts.compact.join(" | ")
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

      def evidence_line
        "evidence: #{ranked.map { |rule, violations| "#{rule}=#{violations.size}" }.join(" ")}"
      end

      def violation_line(violation)
        parts = ["  L#{violation[:line]}", violation[:message][0, CommandRegistry::VIOLATION_TRUNCATE]]
        parts << "conf=#{format('%.2f', violation[:confidence].to_f)}" if violation[:confidence]
        parts << "files=#{Array(violation[:files]).size}" if violation[:files]
        parts << "why=#{violation[:why].to_s[0, 80]}" if violation[:why]
        parts << "genealogy=#{Array(violation[:genealogy]).join(' → ')}" if violation[:genealogy]
        parts << "impact=#{impact_summary(violation[:impact_radius])}" if violation[:impact_radius]
        parts.join(" | ")
      end

      def omitted_count
        ranked.drop(CommandRegistry::SCAN_RULE_GROUP_LIMIT).sum { |_, violations| violations.size }
      end

      def omitted_line
        "#{omitted_count} more violation(s) omitted"
      end

      def cross_file_drifts_line
        clusters = cross_file_duplicate_clusters
        return if clusters.empty?

        summary = clusters.first(3).map do |cluster|
          "#{cluster[:rule]}×#{cluster[:count]}#{cluster[:files] > 1 ? " in #{cluster[:files]} files" : ""}"
        end.join(" ")
        "cross-file DRY: #{summary}"
      end

      def confidence_histogram_line
        buckets = confidence_histogram
        return if buckets.empty?

        "confidence: #{buckets.map { |label, count| "#{label}=#{count}" }.join(" ")}"
      end

      def confidence_histogram
        clustered_violations.each_with_object(Hash.new(0)) do |violation, buckets|
          next if violation[:confidence].nil?

          conf = violation[:confidence].to_f
          label =
            if conf < 0.25 then "0.0-0.24"
            elsif conf < 0.5 then "0.25-0.49"
            elsif conf < 0.75 then "0.50-0.74"
            else "0.75-1.0"
            end
          buckets[label] += 1
        end.sort.to_h
      end

      def impact_radius(cluster)
        {
          files_affected: Array(cluster.map { |v| v[:file] }.compact.uniq).size,
          occurrences: cluster.size,
          severity_multiplier: severity_multiplier(cluster.first[:severity]),
        }
      end

      def impact_summary(radius)
        return "" unless radius.is_a?(Hash)

        "files=#{radius[:files_affected]} occ=#{radius[:occurrences]} x#{format('%.2f', radius[:severity_multiplier])}"
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
