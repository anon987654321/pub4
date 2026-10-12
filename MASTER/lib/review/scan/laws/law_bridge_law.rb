# frozen_string_literal: true

require File.join(Master::ROOT, "law", "definition")

module Master
  module Review
    module Scan
      module Laws
        # Bridges law/*.rb into the scanner. Each Law::Rule proved itself against
        # its own bad/good fixture at load, so a hit here is a hit a fixture already
        # vouches for. YamlDeclarativeLaw yields to any id defined here.
        class LawBridgeLaw < Law
          def self.auto_build? = false

          declare id: "law_bridge", severity: :warning, description: "law/ — executable rules with fixtures"

          def initialize(root: Master::ROOT)
            super()
            @root = root
            law_root = if File.file?(File.join(root, "law", "definition.rb"))
              root
            elsif File.file?(File.join(root, "MASTER", "law", "definition.rb"))
              File.join(root, "MASTER")
            else
              Master::ROOT
            end
            ::Law.load_all(File.join(law_root, "law")) if ::Law.definitions.empty?
          end

          def check(code, path:)
            # Two distinct deterministic sweeps. A detector is assigned only
            # to the stream declared by its Law::Definition#mode; the capability
            # audit reports the other stream as a gap instead of pretending this
            # detector can answer both questions.
            %i[violation opportunity].flat_map do |mode|
              check_stream(code, path:, mode:)
            end
          end

          def check_stream(code, path:, mode:)
            lang = language(path)&.to_sym
            ::Law.definitions.each_value.flat_map do |law|
              next [] unless law.enforceable?
              next [] unless law.scannable?
              next [] unless law.mode.to_sym == mode
              next [] unless law.applies?(path, lang)

              stream = mode == :opportunity ? :lexical_opportunities : :lexical_violations
              law.scan(code, file: path).map do |hit|
                Finding.build(
                  law: law.id.to_s,
                  message: "#{law.id}: #{law.fix}",
                  line: hit.line,
                  severity: severity_for(law.severity),
                  tags: [law.id.to_s, stream, mode],
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
