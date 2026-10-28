# frozen_string_literal: true

require "date"
require "set"

module Master
  module Fix
    # Asserts priority-ranked constitutional entries in data/laws.yml are not
    # prose-only: each must have an executable detector, tag coverage, or an
    # explicit deferred enforcement with a future expiry.
    class LawParity
      # Keep the ceiling wide enough to include every priority-ranked
      # constitutional row currently declared. The parity gate must expose
      # coverage debt; lowering the cutoff must not make a gap disappear.
      MAX_PRIORITY = 8
      LAWS_PATH = File.join(Master::ROOT, "data", "laws.yml").freeze

      Gap = Data.define(:id, :priority, :tier, :reason)
      COVERAGE_MODES = %w[deterministic semantic tagged deferred].freeze
      OVERLAY_FIELDS = %w[severity enforcement coverage_mode detector_ids coverage expires_on].freeze

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
            id:,
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
        summary = priority_constitutional_entries.map do |id, spec|
          mode = spec["coverage_mode"].to_s
          "#{id}=#{mode.empty? ? "undeclared" : mode}"
        end.join(", ")
        return "law_parity: ok (priority<=#{MAX_PRIORITY} constitutional; coverage=#{summary})" if gaps.empty?

        lines = gaps.map { |g| "  #{g.id} (priority #{g.priority}): #{g.reason}" }
        "law_parity: #{gaps.size} gap(s)\n#{lines.join("\n")}"
      end

      private

      def priority_constitutional_entries
        data = @laws_path ? Master.load_yaml(@laws_path) : Master.load_laws(root: @root)
        raise "laws.yml root must be a non-empty mapping" unless data.is_a?(Hash) && !data.empty?

        overlay_path = File.join(File.dirname(@laws_file), "law_enforcement.yml")
        if File.file?(overlay_path)
          overlay = Master.load_yaml(overlay_path) || {}
          raise "law_enforcement.yml root must be a mapping" unless overlay.is_a?(Hash)

          overlay.each do |id, extra|
            name = id.to_s
            raise "law_enforcement.yml entry #{name} must be a mapping" unless extra.is_a?(Hash)

            original = data[name]
            unless original.is_a?(Hash) && original["tier"].to_s == "constitutional" && original.key?("priority")
              raise "law_enforcement.yml entry #{name} does not resolve to a priority-ranked constitutional Law in laws.yml"
            end

            unknown = extra.keys.map(&:to_s) - OVERLAY_FIELDS
            raise "law_enforcement.yml entry #{name} has unknown field(s): #{unknown.join(', ')}" unless unknown.empty?

            data[name] = original.merge(extra)
          end
        end

        data.select do |_id, spec|
          spec.is_a?(Hash) &&
            spec["tier"].to_s == "constitutional" &&
            spec.key?("priority") &&
            Integer(spec["priority"]) <= MAX_PRIORITY
        end
      end

      def covered?(id, spec, detectors, tags)
        mode = spec["coverage_mode"].to_s
        return false unless COVERAGE_MODES.include?(mode)
        return deferred_valid?(spec) if mode == "deferred"
        return semantic_law_ids.include?(id.to_s) if mode == "semantic"

        if mode == "deterministic"
          explicit = Array(spec["detector_ids"]).map(&:to_s)
          candidates = explicit.empty? ? [id.to_s] : explicit
          return candidates.any? { |candidate| detectors.any? { |detector| detector.casecmp?(candidate) } }
        end

        if mode == "tagged" && spec["coverage"].to_s == "tagged_detectors"
          return tags.include?(id.to_s.upcase) || tags.include?(id.to_s)
        end
        false
      end

      def deferred_valid?(spec)
        return false unless spec["enforcement"].to_s == "deferred"

        expires = spec["expires_on"].to_s
        return false if expires.empty?

        Date.parse(expires) >= Date.today
      rescue ArgumentError
        false
      end

      def gap_reason(_id, spec)
        mode = spec["coverage_mode"].to_s
        return "missing explicit coverage_mode" if mode.empty?
        return "unknown coverage_mode #{mode}" unless COVERAGE_MODES.include?(mode)
        if mode == "deferred"
          exp = spec["expires_on"].to_s
          return "deferred without expires_on" if exp.empty?
          return "deferred expired on #{exp}" unless deferred_valid?(spec)
        end
        "declared #{mode} coverage has no matching evidence"
      end

      def registered_detector_ids
        ids = Set.new
        require_relative "../../law/definition" unless defined?(::Law)
        ::Law.load_all if ::Law.respond_to?(:load_all)
        ::Law.definitions.each do |id, definition|
          ids << id.to_s if definition.respond_to?(:detect) && definition.detect
        end
        ids.merge(scan_registry_ids)
        ids
      rescue StandardError, ScriptError => e
        Master::Ground::Swallow.log(e, context: "Fix::LawParity.registered_detector_ids", severity: :load_bearing)
        raise
      end

      def semantic_law_ids
        return @semantic_law_ids if @semantic_law_ids

        require_relative "../../law/definition" unless defined?(::Law)
        ::Law.load_all if ::Law.respond_to?(:load_all)
        @semantic_law_ids = ::Law.definitions.filter_map do |id, definition|
          id.to_s if definition.respond_to?(:semantic?) && definition.semantic?
        end
      rescue StandardError, ScriptError => e
        Master::Ground::Swallow.log(e, context: "Fix::LawParity.semantic_law_ids", severity: :load_bearing)
        raise
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
        ::Law.definitions.each_key { |key| ids << key.to_s } if defined?(::Law) && ::Law.respond_to?(:definitions)
        ids
      rescue StandardError, ScriptError => e
        Master::Ground::Swallow.log(e, context: "Fix::LawParity.law_pack_ids", severity: :load_bearing)
        raise
      end

      def scan_registry_ids
        ids = Set.new
        return ids unless File.file?(File.expand_path("../review/scan/law.rb", __dir__))

        require_relative "../review/scan/law_dsl"
        Master::Review::Scan::Law.registry.each do |klass|
          declaration = klass.respond_to?(:declaration) ? klass.declaration : nil
          ids << declaration[:id].to_s if declaration && declaration[:id]
        end
        ids
      rescue StandardError, ScriptError => e
        Master::Ground::Swallow.log(e, context: "Fix::LawParity.scan_registry_ids", severity: :load_bearing)
        raise
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
