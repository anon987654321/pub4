# frozen_string_literal: true

require "date"
require "set"

module Master
  module Fix
    # Asserts priority-ranked constitutional entries in data/laws.yml are not
    # prose-only: each must have a deterministic detector (a Law.define with a
    # detect block, or a scan-registry detector under its id), a registry
    # detector carrying its tag, or an explicit deferred enforcement with a
    # future expiry. A Law that only asks a model question is semantic coverage,
    # reported apart from the gaps it still is.
    class LawParity
      # Keep the ceiling wide enough to include every priority-ranked
      # constitutional row currently declared. The parity gate must expose
      # coverage debt; lowering the cutoff must not make a gap disappear.
      MAX_PRIORITY = 8
      LAWS_PATH = File.join(Master::ROOT, "data", "laws.yml").freeze

      Gap = Data.define(:id, :priority, :tier, :reason)

      def initialize(root: Master::ROOT, laws_path: nil)
        @root = File.expand_path(Master.master_root(root:))
        @laws_path = laws_path
        @laws_file = laws_path || File.join(@root, "data", "laws.yml")
      end

      def call
        entries = priority_constitutional_entries
        detectors = registered_detector_ids
        tags = registered_tag_names
        gaps = []

        entries.each do |id, spec|
          next if covered?(id, spec, detectors, tags)

          gaps << Gap.new(
            id: id,
            priority: spec["priority"],
            tier: spec["tier"],
            reason: gap_reason(id, spec),
          )
        end

        gaps
      end

      def ok?
        call.empty?
      end

      def report
        gaps = call
        tally = coverage.values.tally.sort.map { |kind, count| "#{kind}=#{count}" }.join(" ")
        return "law_parity: ok (priority<=#{MAX_PRIORITY} constitutional covered; #{tally})" if gaps.empty?

        lines = gaps.map { |g| "  #{g.id} (priority #{g.priority}): #{g.reason}" }
        "law_parity: #{gaps.size} gap(s) (#{tally})\n#{lines.join("\n")}"
      end

      # How each priority Law is covered: :deterministic, :tagged, :deferred,
      # :semantic_only (an ask with no detector) or :none.
      def coverage
        priority_constitutional_entries.to_h { |id, spec| [id, coverage_kind(id, spec)] }
      end

      private

      def priority_constitutional_entries
        data = @laws_path ? Master.load_yaml(@laws_path) : Master.load_laws(root: @root)
        raise "laws.yml root must be a non-empty mapping" unless data.is_a?(Hash) && !data.empty?

        overlay_path = File.join(File.dirname(@laws_file), "law_enforcement.yml")
        if File.file?(overlay_path)
          overlay = Master.load_yaml(overlay_path) || {}
          overlay.each do |id, extra|
            next unless extra.is_a?(Hash) && data[id].is_a?(Hash)

            data[id] = data[id].merge(extra)
          end
        end

        data.select do |_id, spec|
          spec.is_a?(Hash) &&
            spec["tier"].to_s == "constitutional" &&
            spec.key?("priority") &&
            Integer(spec["priority"]) <= MAX_PRIORITY
        end
      end

      def coverage_kind(id, spec)
        return :deferred if deferred_valid?(spec)
        return :deterministic if detector_covered?(id, spec, registered_detector_ids)
        return :tagged if tag_covered?(id, spec, registered_tag_names)

        semantic_ids.include?(id.to_s) ? :semantic_only : :none
      end

      def covered?(id, spec, detectors, tags)
        deferred_valid?(spec) || detector_covered?(id, spec, detectors) || tag_covered?(id, spec, tags)
      end

      def detector_covered?(id, spec, detectors)
        ([id.to_s] + Array(spec["detector_ids"]).map(&:to_s)).any? { |name| detectors.include?(name.downcase) }
      end

      def tag_covered?(id, spec, tags)
        spec["coverage"].to_s == "tagged_detectors" && tags.include?(id.to_s.upcase)
      end

      def deferred_valid?(spec)
        return false unless spec["enforcement"].to_s == "deferred"

        expires = spec["expires_on"].to_s
        return false if expires.empty?

        Date.parse(expires) >= Date.today
      rescue ArgumentError
        false
      end

      def gap_reason(id, spec)
        if spec["enforcement"].to_s == "deferred"
          exp = spec["expires_on"].to_s
          return "deferred without expires_on" if exp.empty?

          return "deferred expired on #{exp}"
        end

        return "semantic only: the Law asks a model question and has no deterministic detector" if
          semantic_ids.include?(id.to_s)

        "no detector, detector_ids, tagged coverage, or valid deferred enforcement"
      end

      # Ids, downcased, that something can run without a model: a Law.define
      # whose detect is set, or a scan-registry detector. A definition that only
      # asks or practises is not one, and neither is a Law.define in source text.
      def registered_detector_ids
        @registered_detector_ids ||= (law_pack_ids + scan_registry_ids).to_set(&:downcase)
      end

      def semantic_ids
        @semantic_ids ||= begin
          law_pack_ids
          ::Law.definitions.values.select { |law| law.ask && !law.detect }.to_set { |law| law.id.to_s }
        end
      end

      def registered_tag_names
        tags = Set.new
        scan_registry_tags.each { |t| tags << t }
        tags
      end

      def law_pack_ids
        ids = Set.new
        require_relative "../../law/definition" unless defined?(::Law)
        ::Law.load_all if ::Law.respond_to?(:load_all)
        ::Law.definitions.each_value { |law| ids << law.id.to_s if law.detect }
        ids
      rescue StandardError, ScriptError => e
        Master::Ground::Swallow.log(e, context: "Fix::LawParity.law_pack_ids", severity: :load_bearing)
        raise
      end

      def scan_registry_ids
        return Set.new unless File.file?(File.expand_path("../review/scan/law.rb", __dir__))

        require_relative "../review/scan/law_dsl"
        Master::Review::Scan::Law.registry.filter_map { |klass| registry_id(klass) }.to_set
      rescue StandardError, ScriptError => e
        Master::Ground::Swallow.log(e, context: "Fix::LawParity.scan_registry_ids", severity: :load_bearing)
        raise
      end

      # LawDSL classes carry their id as dsl_id; declared classes in their declaration.
      def registry_id(klass)
        id = klass.dsl_id if klass.singleton_class.method_defined?(:dsl_id)
        id ||= klass.declaration&.[](:id)
        id&.to_s
      end

      def scan_registry_tags
        tags = Set.new
        require_relative "../review/scan/law_dsl"
        Master::Review::Scan::Law.registry.each do |klass|
          Array(klass.dsl_tags).each { |tag| tags << tag.to_s.upcase }
          declaration = klass.respond_to?(:declaration) ? klass.declaration : nil
          Array(declaration && declaration[:law_tags]).each { |tag| tags << tag.to_s.upcase }
        end
        tags
      rescue StandardError, ScriptError => e
        Master::Ground::Swallow.log(e, context: "Fix::LawParity.scan_registry_tags", severity: :load_bearing)
        raise
      end
    end
  end
end
