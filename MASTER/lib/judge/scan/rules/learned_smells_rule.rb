# frozen_string_literal: true

module Master
  module Judge
    module Scan
      module Rules
        class LearnedSmellsRule < Rule
          def initialize(root: Master::ROOT)
            super()
            @id = "LEARNED_SMELLS"
            @description = "session-learned smell patterns from rules.yml"
            @severity = :warning
            @rule_tags = %i[LEARNED_SMELLS SESSION]
            @auto_fix = false
            @root = root
            reload_learned_smells!
          end

          def check(code, path:)
            reload_learned_smells_if_stale
            return [] if @learned_smells.empty?

            language = self.language(path)&.to_s
            @learned_smells.flat_map do |smell|
              next [] unless applies_to_smell?(smell, language)

              pattern = smell_pattern(smell)
              next [] unless pattern

              code.each_line.with_index(1).filter_map do |line, line_number|
                next unless line.match?(pattern)

                rule_id = smell["id"].to_s
                Finding.build(
                  rule: rule_id.empty? ? @id : rule_id,
                  message: smell_message(smell),
                  line: line_number,
                  severity: smell_severity(smell),
                  tags: smell_tags(smell),
                  reversibility: smell["reversibility"],
                  blast_radius: smell["blast_radius"]
                )
              end
            end
          rescue StandardError => e
            [Finding.build(rule: @id, message: "learned smell scan error — #{e.message}", line: 1,
              severity: :warning, tags: %i[LEARNED_SMELLS])]
          end

          private

          def reload_learned_smells_if_stale
            return if @rules_mtime == rules_mtime

            reload_learned_smells!
          end

          def reload_learned_smells!
            @learned_smells = Array(Master.load_yaml(rules_path)&.fetch("learned_smells", [])).select { |item| item.is_a?(Hash) }
            @rules_mtime = rules_mtime
          rescue StandardError
            @learned_smells = []
            @rules_mtime = nil
          end

          def rules_path
            File.join(@root, "data", "rules.yml")
          end

          def rules_mtime
            File.mtime(rules_path).to_i
          rescue StandardError
            nil
          end

          def smell_pattern(smell)
            raw = smell["pattern"] || smell["regex"] || smell["detect"]
            return unless raw

            Regexp.new(raw.to_s)
          rescue RegexpError
            nil
          end

          def smell_message(smell)
            smell["message"] || smell["description"] || smell["name"] || smell["id"] || "learned smell"
          end

          def smell_severity(smell)
            (smell["severity"] || "warning").to_sym
          end

          def smell_tags(smell)
            Array(smell["tags"]).map(&:to_sym) + %i[LEARNED_SMELL]
          end

          def applies_to_smell?(smell, language)
            mediums = Array(smell["mediums"] || smell["medium"] || smell["applies_to"]).compact.map(&:to_s)
            return true if mediums.empty?
            return false if language.nil?

            mediums.include?(language)
          end
        end
      end
    end
  end
end
