# frozen_string_literal: true

module Master
  module Ground
    module Orders
      # Continuous self-audit: scans lib/ against the axioms and reports drift.
      class ConstitutionDrift < Base
        STATE_PATH = "runtime/constitution_drift.json"

        def call
          scanner = @container[:scanner]
          return Result.err("no scanner in container") unless scanner

          report = build_report(scanner)
          publish_drift(report)
          persist(report)
          Result.ok(report)
        rescue StandardError => e
          Result.err(e.message)
        end

        private

        # total, delta-since-last-run, and per-axiom counts.
        def build_report(scanner)
          by_axiom = tally_violations(scanner)
          total = by_axiom.values.sum
          delta = total - load_previous[:total].to_i
          { total:, delta:, by_axiom:, worst: by_axiom.max_by { |_, n| n }&.first }
        end

        def lib_files
          Dir.glob(File.join(root, "lib", "**", "*.rb"))
             .reject { |p| p.include?("/knowledge/") || p.include?("/vendor/") }
             .sort
        end

        # axiom_tag => violation count, across all of lib/.
        def tally_violations(scanner)
          lib_files.each_with_object(Hash.new(0)) do |path, acc|
            result = scanner.scan(path, depth: :deep)
            next unless result.ok?
            result.value!.each { |f| Array(f[:tags]).each { |t| acc[t.to_s] += 1 } }
          end
        end

        # improved | regressed | steady — caught the moment a defect lands.
        def publish_drift(report)
          delta = report[:delta]
          kind = delta.negative? ? "improved" : (delta.positive? ? "regressed" : "steady")
          bus&.publish("constitution_drift:#{kind}", **report)
        end

        def state_file = File.join(root, STATE_PATH)

        def load_previous
          return { total: 0 } unless File.exist?(state_file)

          JSON.parse(File.read(state_file), symbolize_names: true)
        rescue StandardError => e
          Swallow.log(e, context: "constitution_drift.load_previous", event_bus: bus)
          { total: 0 }
        end

        def persist(report)
          FileUtils.mkdir_p(File.dirname(state_file))
          record = report.slice(:total, :by_axiom).merge(at: Time.now.utc.iso8601)
          File.write(state_file, JSON.pretty_generate(record))
        rescue StandardError => e
          Swallow.log(e, context: "constitution_drift.persist", event_bus: bus)
        end
      end
    end
  end
end
