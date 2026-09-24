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

        # With a block, each file's findings are yielded the moment that file
        # is read, so repairs can start while the rest of the target is still
        # being scanned. The return value is the whole scan either way.
        def violations(files, &on_file)
          raw = files.flat_map do |path|
            next [] unless File.exist?(path)

            file_violations(path).tap do |found|
              on_file&.call(path, resolve(found)) if found.any?
            end
          end
          resolve(raw)
        end

        private

        def file_violations(path)
          result = Result.wrap(@scanner.scan(path))
          raise "fix scan failed for #{path}: #{result.message}" unless result.ok?

          findings = result.value!
          stream_scan_progress(path, findings)
          findings
            .select { |finding| Severity.at_least?(finding.fetch(:severity, :warning), :warning) }
            .map { |finding| Violation.from_finding(finding, file: path.delete_prefix("#{@root}/")) }
        end

        def resolve(raw)
          rows = @conflict_resolver ? @conflict_resolver.filter_findings(raw.map(&:to_h)) : raw.map(&:to_h)
          rows.map { |row| row.transform_keys(&:to_sym) }
        end

        def stream_scan_progress(path, findings)
          count = findings.size
          return unless count.positive?

          rel = path.delete_prefix("#{@root}/")
          @bus&.publish("fix_loop:scan_progress", file: rel, count:)
        end
      end
    end
  end
end
