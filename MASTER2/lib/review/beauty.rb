# frozen_string_literal: true

# BeautyScorer -- detects aesthetic virtues and scores them positively.
# Counterpart to the enforcer: where the enforcer counts violations,
# BeautyScorer counts virtues. Both run on every review pass.
#
# Public interface:
#   BeautyScorer.score(code, filename:) -> { score: Integer, virtues: Array }
#   BeautyScorer.exemplar?(score)        -> Boolean
#   BeautyScorer.register_exemplar(name:, file:, lines:, score:, virtue:, why:)

module MASTER
  module Review
    module BeautyScorer
      extend self

      EXEMPLAR_THRESHOLD = 6  # beauty score at which a method qualifies for exemplar registry

      # Virtue detectors -- positive signal, not negative.
      # Each returns points if the pattern is present.
      VIRTUES = [
        {
          id:      :zen_method,
          points:  3,
          axiom:   "ZEN_METHOD",
          test:    ->(code, _f) {
            # Methods ≤ 7 lines, no rescue inside def, nesting ≤ 1
            methods = code.scan(/def \w+.*?^  end/m)
            methods.any? do |m|
              lines = m.lines.length
              no_rescue = !m.match?(/\brescue\b/)
              shallow   = m.scan(/\b(if|unless|case|while|until|loop)\b/).length <= 1
              lines <= 9 && no_rescue && shallow
            end
          },
          label: "zen method -- single responsibility, minimal, no rescue",
        },
        {
          id:      :no_comment_needed,
          points:  2,
          axiom:   "AESTHETIC_VIRTUE",
          test:    ->(code, filename) {
            return false unless filename.to_s.end_with?(".rb")

            # Ruby file with zero # comments (except frozen_string_literal)
            comment_lines = code.lines.count { |l| l.strip.start_with?("#") && !l.include?("frozen_string_literal") }
            total_lines   = code.lines.reject { |l| l.strip.empty? }.length
            comment_lines == 0 && total_lines > 3
          },
          label: "no comments needed -- code is self-evident",
        },
        {
          id:      :perfect_name,
          points:  2,
          axiom:   "AESTHETIC_VIRTUE",
          test:    ->(code, _f) {
            # Method names that are single active verbs or specific domain nouns
            # (no filler prefixes, no vague nouns)
            methods = code.scan(/def (\w+)/).flatten
            return false if methods.empty?

            filler  = /\A(get_|do_|perform_|handle_|process_|run_|execute_|manage_|data|info|thing|stuff)\z/i
            perfect = methods.reject { |m| m.match?(filler) || m.length > 20 }
            perfect.length.to_f / methods.length >= 0.8
          },
          label: "80%+ of method names are specific active verbs",
        },
        {
          id:      :composable_chain,
          points:  1,
          axiom:   "AESTHETIC_VIRTUE",
          test:    ->(code, _f) {
            # Detect method chains: x.load.enforce.reflow style (3+ chained calls)
            code.match?(/\w+(?:\.\w+\(?\)?){3,}/)
          },
          label: "composable method chain -- reads as natural sequence",
        },
        {
          id:      :dense_expressive,
          points:  1,
          axiom:   "AESTHETIC_VIRTUE",
          test:    ->(code, _f) {
            # Methods that do ≥ 3 operations in ≤ 5 lines
            methods = code.scan(/def \w+.*?^  end/m)
            methods.any? do |m|
              lines = m.lines.reject { |l| l.strip.empty? }.length
              ops   = m.scan(/\b(map|select|reject|reduce|each|flat_map|then|yield|return|raise)\b/).length
              lines <= 7 && ops >= 3
            end
          },
          label: "dense and expressive -- many operations, few lines",
        },
        {
          id:      :domain_language_pure,
          points:  2,
          axiom:   "AESTHETIC_VIRTUE",
          test:    ->(code, _f) {
            # All method names share a semantic family
            # Heuristic: check if ≥ 70% of non-trivial method names share a root domain
            methods = code.scan(/def (\w+)/).flatten.reject { |m| m.length < 4 }
            return false if methods.length < 4

            # Legal/judicial domain
            judicial = methods.count { |m| m.match?(/enforce|violate|acquit|veto|mandate|comply|adjudicate|verdict|sanction/) }
            # Construction domain
            build    = methods.count { |m| m.match?(/build|construct|assemble|compose|wire|mount|attach|scaffold/) }
            # Data flow domain
            flow     = methods.count { |m| m.match?(/load|parse|transform|emit|pipe|stream|flush|drain|filter/) }

            best = [judicial, build, flow].max
            best.to_f / methods.length >= 0.5
          },
          label: "domain language pure -- names drawn from one semantic field",
        },
      ].freeze

      def score(code, filename: "code")
        virtues_found = []
        total = 0

        VIRTUES.each do |v|
          next unless v[:test].call(code, filename)

          total += v[:points]
          virtues_found << { id: v[:id], points: v[:points], label: v[:label], axiom: v[:axiom] }
        end

        { score: total, virtues: virtues_found }
      end

      def exemplar?(score)
        score >= EXEMPLAR_THRESHOLD
      end

      # Store an exemplar in data/exemplars.yml
      def register_exemplar(name:, file:, lines: nil, score: 0, virtue: nil, why: nil)
        path = File.join(MASTER.root, "data", "exemplars.yml")
        data = begin
          YAML.safe_load_file(path) || { "exemplars" => [] }
        rescue StandardError
          { "exemplars" => [] }
        end
        data["exemplars"] ||= []

        # Avoid duplicates
        return if data["exemplars"].any? { |e| e["name"] == name && e["file"] == file }

        data["exemplars"] << {
          "name"          => name,
          "file"          => file,
          "lines"         => lines,
          "beauty_score"  => score,
          "virtue"        => virtue&.to_s,
          "why"           => why,
          "recorded_at"   => Time.now.strftime("%Y-%m-%d"),
        }.compact

        File.write(path, YAML.dump(data))
      rescue StandardError
        nil  # never raise -- beauty scoring is advisory
      end

      # Inject top exemplars into LLM system message
      def exemplars_prompt(max: 3)
        path = File.join(MASTER.root, "data", "exemplars.yml")
        data = begin
          YAML.safe_load_file(path) || {}
        rescue StandardError
          {}
        end
        list = Array(data["exemplars"])
                 .sort_by { |e| -(e["beauty_score"] || 0) }
                 .first(max)
        return "" if list.empty?

        lines = ["EXEMPLARS (reference these patterns as positive models):"]
        list.each { |e| lines << "  * #{e['name']} in #{e['file']} -- #{e['why']}" }
        lines.join("\n")
      rescue StandardError
        ""
      end
    end
  end
end
