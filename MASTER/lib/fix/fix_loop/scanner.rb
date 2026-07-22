# frozen_string_literal: true

require_relative "../severity"
require_relative "../violation"

module Master
  module Fix
    class FixLoop
      class Scanner
        def initialize(scanner:, root:, bus: nil, conflict_resolver: nil)
          @scanner = scanner
          @root = root
          @bus = bus
          @conflict_resolver = conflict_resolver
        end

        def violations(files)
          raw = files.flat_map do |path|
            next [] unless File.exist?(path)

            result = @scanner.scan(path)
            findings = Result.wrap(result).value_or([])
            stream_scan_progress(path, findings)
            findings
              .select { |finding| Severity.at_least?(finding.fetch(:severity, :warning), :warning) }
              .map { |finding| Violation.from_finding(finding, file: path.delete_prefix("#{@root}/")) }
          end
          rows = @conflict_resolver ? @conflict_resolver.filter_findings(raw.map(&:to_h)) : raw.map(&:to_h)
          rows.map { |row| row.transform_keys(&:to_sym) }
        end

        private

        def stream_scan_progress(path, findings)
          count = findings.size
          return unless count.positive?

          rel = path.delete_prefix("#{@root}/")
          $stdout.puts "scan: #{rel} #{count} violation(s)"
          $stdout.flush
          @bus&.publish("fix_loop:scan_progress", file: rel, count:)
        end
      end
    end
  end
end
