# frozen_string_literal: true

module Master
  module Ground
    # rules.yml preserve_user_intent — block silent behavior changes during refactors.
    class PreserveUserIntent
      REFACTOR_RE = /\b(?:refactor|restructure|reorganize|extract|inline)\b/i.freeze
      APPROVAL_RE = /\b(?:behavior[_-]?change[_-]?approved|approved[_-]?behavior)\b/i.freeze
      DEF_LINE_RE = /^[+-]\s*def\s+(\w+)/.freeze
      RAISE_RE = /^[+-].*\braise\s+([A-Z]\w+)/.freeze
      RETURN_RE = /^[+-].*\breturn\b/.freeze
      LOG_RE = /^[+-].*\b(?:log|logger|puts|warn|error)\b/i.freeze

      def initialize(root: Master::ROOT, config: nil)
        @root = root
        @config = config || load_config
        @forbidden = Array(@config["forbidden_changes_during_refactor"]).freeze
      end

      def refactor_message?(message) = REFACTOR_RE.match?(message.to_s)
      def approved?(message) = APPROVAL_RE.match?(message.to_s)

      def violations(diff_text)
        lines = diff_text.to_s.lines
        hits = []
        hits << "public_method_signature" if @forbidden.include?("public_method_signature") && signature_change?(lines)
        hits << "error_class_raised" if @forbidden.include?("error_class_raised") && raise_change?(lines)
        hits << "return_type_shape" if @forbidden.include?("return_type_shape") && return_change?(lines)
        hits << "log_format_consumed_by_others" if @forbidden.include?("log_format_consumed_by_others") && log_change?(lines)
        hits << "side_effects_order" if @forbidden.include?("side_effects_order") && side_effect_reorder?(lines)
        hits.uniq
      end

      def assert_preserved!(diff_text, message:)
        return Result.ok(:skipped) unless refactor_message?(message)
        return Result.ok(:approved) if approved?(message)

        found = violations(diff_text)
        return Result.ok(:ok) if found.empty?

        Result.err("preserve_user_intent: forbidden during refactor: #{found.join(", ")}", category: :policy)
      end

      private

      def load_config
        Master.load_yaml(Master::RULES_PATH).fetch("preserve_user_intent", {})
      rescue StandardError
        {}
      end

      def signature_change?(lines)
        added = lines.grep(DEF_LINE_RE) { Regexp.last_match(1) }
        removed = lines.grep(/^-\s*def\s+(\w+)/) { Regexp.last_match(1) }
        (added - removed).any? || (removed - added).any?
      end

      def raise_change?(lines) = lines.any? { |line| line.match?(RAISE_RE) }
      def return_change?(lines) = lines.any? { |line| line.match?(RETURN_RE) }
      def log_change?(lines) = lines.any? { |line| line.match?(LOG_RE) }

      def side_effect_reorder?(lines)
        ops = lines.filter_map do |line|
          next unless line.start_with?("+", "-")
          next if line.start_with?("+++", "---")

          stripped = line[1..].to_s.strip
          next unless stripped.match?(/\b(?:save|write|delete|create|update|publish|emit)\b/i)

          [line[0], stripped]
        end
        added = ops.select { |sign, _| sign == "+" }.map(&:last)
        removed = ops.select { |sign, _| sign == "-" }.map(&:last)
        !added.empty? && !removed.empty? && added != removed
      end
    end
  end
end