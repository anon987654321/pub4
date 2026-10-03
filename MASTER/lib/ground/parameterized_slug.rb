# frozen_string_literal: true

module Master
  module Ground
    # Rails-parameterize slug density for paths — snake_case, Strunk-clean tokens.
    module ParameterizedSlug
      MAX_TOKENS = 4
      FOLD_SUFFIXES = %w[_support _helper _util _helpers _utils].freeze
      FILLER_TOKENS = %w[
        main misc base util helper handlers handler manager service object thing stuff
        tmp old new copy final v2 data info the a an
      ].freeze
      FORBIDDEN_ABBREVS = %w[idx sig tmp buf val ret obj str arr num cnt ptr msg].freeze
      SUSPICIOUS = /\b(tmp|misc|old|new|copy|final\d*|v2|_fixed)\b/i.freeze

      Issue = Data.define(:action, :from, :to, :reason)

      module_function

      def dense_slug(stem)
        meaningful_tokens(stem).first(MAX_TOKENS).join("_")
      end

      def meaningful_tokens(stem)
        stem.to_s.downcase.split("_").reject(&:empty?)
            .reject { |token| FILLER_TOKENS.include?(token) || FORBIDDEN_ABBREVS.include?(token) }
      end

      def filler_only?(stem)
        tokens = stem.to_s.downcase.split("_").reject(&:empty?)
        return false if tokens.empty?

        meaningful_tokens(stem).empty?
      end

      def fold_suffix?(stem)
        value = stem.to_s
        return false unless FOLD_SUFFIXES.any? { |suffix| value.end_with?(suffix) }

        tokens = value.split("_").reject(&:empty?)
        return false if tokens.size >= 3

        true
      end

      def fold_target(stem)
        value = stem.to_s
        FOLD_SUFFIXES.each do |suffix|
          return value.delete_suffix(suffix) if value.end_with?(suffix)
        end
        nil
      end

      def issues_for_stem(stem)
        dense = dense_slug(stem)
        [
          fold_issue(stem),
          density_issue(stem, dense),
          token_count_issue(stem, dense),
          suspicious_issue(stem),
        ].compact.uniq { |row| "#{row.action}:#{row.from}:#{row.to}" }
      end

      def fold_issue(stem)
        return unless fold_suffix?(stem)

        target = fold_target(stem)
        Issue.new(action: "merge", from: stem, to: target, reason: "fold suffix sprawl — merge into #{target}")
      end

      def density_issue(stem, dense)
        if !dense.empty? && dense != stem.to_s
          Issue.new(action: "rename", from: stem, to: dense,
                   reason: "low-density slug — rename to parameterized Strunk-clean path")
        elsif filler_only?(stem)
          Issue.new(action: "rename", from: stem, to: stem,
                   reason: "filler-only slug — rename to concrete parameterized path (Strunk nouns/verbs)")
        end
      end

      def token_count_issue(stem, dense)
        tokens = stem.to_s.split("_").reject(&:empty?)
        return unless tokens.size > MAX_TOKENS && !dense.empty?

        Issue.new(action: "rename", from: stem, to: dense,
                 reason: "slug exceeds #{MAX_TOKENS} tokens — compress to dense parameterized path")
      end

      def suspicious_issue(stem)
        return unless stem.to_s.match?(SUSPICIOUS)

        Issue.new(action: "rename", from: stem, to: stem.to_s.gsub(SUSPICIOUS, "canonical"),
                 reason: "suspicious segment — rename to honest Zeitwerk path")
      end

      def path_issues(path)
        return [] unless path.to_s.end_with?(".rb")

        stem = File.basename(path.to_s, ".rb")
        issues_for_stem(stem)
      end
    end
  end
end
