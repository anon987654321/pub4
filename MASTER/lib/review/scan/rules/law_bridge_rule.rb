# frozen_string_literal: true

require File.join(Master::ROOT, "law", "law")

module Master
  module Review
    module Scan
      module Rules
        # Bridges law/*.rb into the scanner. Each Law::Rule proved itself against
        # its own bad/good fixture at load, so a hit here is a hit a fixture already
        # vouches for. YamlDeclarativeRule yields to any id defined here.
        class LawBridgeRule < Rule
          def self.auto_build? = false

          def initialize(root: Master::ROOT)
            super()
            @id = "law_bridge"
            @description = "law/ — executable rules with fixtures"
            @severity = :warning
            @auto_fix = false
            @root = root
            Law.load_all(File.join(root, "law")) if Law.rules.empty?
          end

          def check(code, path:)
            lang = language(path)&.to_sym
            # law/ files arrive already neutralized: FileProcessor#law_conducted
            # runs Law.conduct at the one read site, so every rule — this
            # bridge and the registry classes alike — sees fixtures and
            # detectors as declarations, not conduct.
            Law.rules.each_value.flat_map do |rule|
              next [] unless rule.applies?(path, lang)

              rule.scan(code, file: path).map do |hit|
                Finding.build(
                  rule: rule.id.to_s.downcase,
                  message: "#{rule.id}: #{rule.fix}",
                  line: hit.line,
                  severity: severity_for(rule.severity),
                  tags: [rule.id.to_s],
                )
              end
            end
          end

          private

          def severity_for(sev)
            { warn: :warning, error: :error, info: :info }.fetch(sev, sev)
          end
        end
      end
    end
  end
end
