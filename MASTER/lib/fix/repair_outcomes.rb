# frozen_string_literal: true

require "fileutils"
require "json"
require "time"

module Master
  module Fix
    # What happened to each class of fix, so the next prompt can say what to
    # avoid and what works here. A class is law id + pattern (the file type, or
    # a transform the caller names) + app area (the path's first two segments).
    # Counts decay with a half-life, so an old rejection stops forbidding a fix
    # the code has since made possible, and the file stays bounded.
    class RepairOutcomes
      PATH = File.join(".master", "fix_outcomes.json")
      HALF_LIFE_DAYS = 14.0
      MAX_CLASSES = 200
      MIN_WEIGHT = 0.5
      AVOID_MIN = 3.0
      AVOID_RATIO = 0.7
      WORKS_MIN = 2.0
      WORKS_RATIO = 0.6
      SUMMARY_LINES = 6
      SUMMARY_BYTES = 900
      LOCK = Mutex.new

      # RepairLoop's per-violation outcome symbols, folded to three verdicts.
      ACCEPTED = %i[applied commit_refused].freeze
      REVERTED = %i[rejected].freeze
      REJECTED = %i[no_proposal reflexion_rejected consensus_rejected].freeze

      def initialize(root:, clock: -> { Time.now })
        root = File.expand_path(root)
        root = Master::ROOT if root == Master::REPO_ROOT
        @file = File.join(root, PATH)
        @repo = File.basename(root) == "MASTER" ? File.dirname(root) : root
        @clock = clock
      end

      # outcomes is a repair's breakdown, { outcome_symbol => count }.
      def record(path, law_ids, outcomes, pattern: nil)
        tallies = fold(outcomes)
        return if tallies.empty?

        LOCK.synchronize do
          data = load
          law_ids.each do |law|
            key = class_key(law, pattern || extension(path), area(path))
            tallies.each { |verdict, reason, count| add(data, key, verdict, reason, count) }
          end
          prune(data)
          save(data)
        end
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "Fix::RepairOutcomes.record")
      end

      # Compact prompt text; nil when there is nothing worth saying.
      def summary
        rows = decayed(load)
        avoid = rows.select { |row| row[:bad] >= AVOID_MIN && row[:bad] / row[:total] >= AVOID_RATIO }
        works = rows.select { |row| row[:accepted] >= WORKS_MIN && row[:accepted] / row[:total] >= WORKS_RATIO }
        return if avoid.empty? && works.empty?

        lines = ["fix history (decayed; do not re-propose rejected classes):"]
        avoid.sort_by { |row| -row[:bad] }.first(SUMMARY_LINES).each do |row|
          lines << "avoid #{row[:key]}: #{row[:bad].round} rejected/reverted, mostly #{row[:reason]}"
        end
        works.sort_by { |row| -row[:accepted] }.first(SUMMARY_LINES).each do |row|
          lines << "works #{row[:key]}: #{row[:accepted].round} accepted"
        end
        lines.join("\n").byteslice(0, SUMMARY_BYTES).scrub("")
      end

      def self.summary(root)
        new(root:).summary
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "Fix::RepairOutcomes.summary")
        nil
      end

      private

      def fold(outcomes)
        outcomes.to_h.filter_map do |outcome, count|
          sym = outcome.to_sym
          verdict = if ACCEPTED.include?(sym) then "accepted"
                    elsif REVERTED.include?(sym) then "reverted"
                    elsif REJECTED.include?(sym) then "rejected"
                    end
          [verdict, sym.to_s, count.to_i] if verdict && count.to_i.positive?
        end
      end

      def class_key(law, pattern, area) = [law, pattern, area].join(" | ")
      def extension(path) = File.extname(path.to_s).delete_prefix(".").then { |ext| ext.empty? ? "none" : ext }

      def area(path)
        full = File.expand_path(path.to_s, @repo)
        return "other" unless full.start_with?("#{@repo}/")

        full.delete_prefix("#{@repo}/").split("/").first(2).join("/")
      end

      def add(data, key, verdict, reason, count)
        row = (data["classes"][key] ||= { "accepted" => 0.0, "rejected" => 0.0, "reverted" => 0.0, "reasons" => {} })
        decay_row(row, data["classes"][key]["at"])
        row[verdict] += count
        row["reasons"][reason] = row["reasons"].fetch(reason, 0.0) + count unless verdict == "accepted"
        row["at"] = @clock.call.to_i
      end

      def factor(at)
        age_days = (@clock.call.to_i - at.to_i) / 86_400.0
        at ? 0.5**(age_days / HALF_LIFE_DAYS) : 1.0
      end

      def decay_row(row, at)
        scale = factor(at)
        %w[accepted rejected reverted].each { |name| row[name] = (row[name] * scale).round(3) }
        row["reasons"].transform_values! { |value| (value * scale).round(3) }
      end

      def decayed(data)
        data["classes"].filter_map do |key, row|
          scale = factor(row["at"])
          accepted, rejected, reverted = %w[accepted rejected reverted].map { |name| row[name].to_f * scale }
          total = accepted + rejected + reverted
          next if total < MIN_WEIGHT

          reason = row["reasons"].max_by { |_, value| value }&.first || "n/a"
          { key:, accepted:, bad: rejected + reverted, total:, reason: }
        end
      end

      def prune(data)
        weighed = decayed(data).to_h { |row| [row[:key], row[:total]] }
        data["classes"].select! { |key, _| weighed.key?(key) }
        return if data["classes"].size <= MAX_CLASSES

        keep = weighed.sort_by { |_, weight| -weight }.first(MAX_CLASSES).map(&:first)
        data["classes"].select! { |key, _| keep.include?(key) }
      end

      def load
        base = { "schema" => 1, "classes" => {} }
        return base unless File.file?(@file)

        base.merge(JSON.parse(File.read(@file)))
      rescue JSON::ParserError
        base
      end

      def save(data)
        FileUtils.mkdir_p(File.dirname(@file))
        File.write(@file, JSON.pretty_generate(data) + "\n")
      end
    end
  end
end
