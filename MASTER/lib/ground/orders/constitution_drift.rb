# frozen_string_literal: true

module Master
  module Ground
  module Orders
    # Continuous constitutional self-audit. ArchitectureAudit watches data/
    # shape; this watches lib/ *behaviour* against the declared axioms.
    #
    # Scans every Ruby file under lib/, tallies findings by axiom tag, and
    # compares the total to the previous run stored in
    # runtime/constitution_drift.json. Emits one of three bus events:
    #
    #   constitution_drift:improved  — fewer violations than last run
    #   constitution_drift:regressed — more violations (a new defect landed)
    #   constitution_drift:steady    — unchanged
    #
    # The point is a tripwire: the constitution stops being enforced only on
    # demand and starts catching regressions the moment they appear.
    class ConstitutionDrift < Base
      STATE_PATH = "runtime/constitution_drift.json"

      def call
        scanner = @container[:scanner]
        return Result.err("no scanner in container") unless scanner

        by_axiom = tally_violations(scanner)
        total    = by_axiom.values.sum
        previous = load_previous
        delta    = total - previous[:total].to_i

        publish_drift(total:, delta:, by_axiom:)
        persist(total:, by_axiom:)

        Result.ok(total:, delta:, by_axiom:)
      rescue StandardError => e
        Result.err(e.message)
      end

      private

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

          result.value!.each do |finding|
            Array(finding[:tags]).each { |tag| acc[tag.to_s] += 1 }
          end
        end
      end

      def publish_drift(total:, delta:, by_axiom:)
        kind =
          if    delta.negative? then "improved"
          elsif delta.positive? then "regressed"
          else  "steady"
          end
        bus&.publish("constitution_drift:#{kind}",
                     total:, delta:, by_axiom:, worst: worst_axiom(by_axiom))
      end

      def worst_axiom(by_axiom)
        by_axiom.max_by { |_, n| n }&.first
      end

      def state_file = File.join(root, STATE_PATH)

      def load_previous
        return { total: 0 } unless File.exist?(state_file)
        JSON.parse(File.read(state_file), symbolize_names: true)
      rescue StandardError => e
        Swallow.log(e, context: "constitution_drift.load_previous", event_bus: bus)
        { total: 0 }
      end

      def persist(total:, by_axiom:)
        FileUtils.mkdir_p(File.dirname(state_file))
        record = { total:, by_axiom:, at: Time.now.utc.iso8601 }
        File.write(state_file, JSON.pretty_generate(record))
      rescue StandardError => e
        Swallow.log(e, context: "constitution_drift.persist", event_bus: bus)
      end
    end
  end
  end
end
