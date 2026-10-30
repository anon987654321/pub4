# frozen_string_literal: true

module Master
  module Review
  module Scan
    require_relative "detector"

      # Adapts the canonical Law::Definition contract to the scanner's
      # finding interface. This is an adapter, not a second Law declaration or
      # registry: identity, severity, scope, fixtures, and repair guidance live
      # with the canonical definition and are audited against laws.yml.
      class CanonicalLawAdapter
        attr_reader :definition

        # A canonical definition scans the text it is handed and nothing else
        # unless it says otherwise, so Fix::Scan::FindingCache may replay its
        # findings for unchanged content.
        def reads_beyond_file? = definition.reads_beyond_file ? true : false

        def initialize(definition)
          raise ArgumentError, "canonical law definition required" unless definition.respond_to?(:id)

          @definition = definition
          @id = definition.id.to_s
        end

        def id = @id
        def description = definition.ask.to_s.empty? ? (definition.practice || definition.fix).to_s : definition.ask.to_s
        def severity = Detector.normalize_severity(definition.severity)
        def law_tags = definition.tags.empty? ? [definition.id.to_s] : definition.tags
        # The catalogue's `autofix: automatic` is the operator's permission for
        # /fix to repair this Law's findings unattended; anything else waits for
        # review. It read `false` here for every Law, so no canonical Law could
        # reach MechanicalAutofix whatever its policy said.
        def auto_fix = definition.autofix == :automatic
        def autofix = definition.autofix
        def languages = Array(definition.languages).map(&:to_s)
        def mode = definition.mode
        def prefetch(_paths) = nil

        def check(code, path:)
          return [] unless definition.enforceable? && definition.scannable?
          return [] unless definition.applies?(path.to_s, Master.language_for(path))

          stream = definition.mode.to_sym == :opportunity ? :lexical_opportunities : :lexical_violations
          definition.scan(code, file: path).map do |hit|
            # A check builds the whole finding — its fix, confidence and radius — through Detector#finding.
            next hit.detail if hit.detail

            Finding.build(
              law: id,
              message: hit.message || "#{id}: #{definition.fix}",
              line: hit.line,
              severity:,
              fix: definition.fix,
              tags: [id, stream, definition.mode],
            )
          end
        rescue StandardError => e
          Master::Ground::Swallow.log(e, context: "CanonicalLawAdapter#check", severity: :load_bearing, path:)
          raise "canonical Law #{id} detector failed for #{path}: #{e.class}: #{e.message}"
        end
      end
    end
  end
end
