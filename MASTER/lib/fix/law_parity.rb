# frozen_string_literal: true

require "date"
require "set"

module Master
  module Fix
    # Asserts priority-ranked constitutional entries in data/laws.yml are not
    # prose-only: each must have an executable detector, tag coverage, or an
    # explicit deferred enforcement with a future expiry.
    class LawParity
      # Audit every priority-ranked constitutional law. At 8, the current
      # uncovered RENDERED_VALUES entry is reported honestly until a tagged
      # detector or an operator-approved deferral is recorded.
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
        return "law_parity: ok (priority<=#{MAX_PRIORITY} constitutional covered)" if gaps.empty?

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

      def covered?(id, spec, detectors, tags)
        return true if deferred_valid?(spec)
        return true if detectors.include?(id.to_s)
        return true if detectors.include?(id.to_s.downcase)

        explicit = Array(spec["detector_ids"]).map(&:to_s)
        return true if explicit.any? { |d| detectors.include?(d) }

        if spec["coverage"].to_s == "tagged_detectors"
          tag = id.to_s.upcase
          return true if tags.include?(tag) || tags.include?(id.to_s)
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

      def gap_reason(id, spec)
        if spec["enforcement"].to_s == "deferred"
          exp = spec["expires_on"].to_s
          return "deferred without expires_on" if exp.empty?

          return "deferred expired on #{exp}"
        end

        "no detector, detector_ids, tagged coverage, or valid deferred enforcement"
      end

      def registered_detector_ids
        ids = Set.new
        ids.merge(law_pack_ids)
        ids.merge(scan_registry_ids)
        ids.merge(law_define_ids_from_source)
        ids
      end

      def registered_tag_names
        tags = Set.new
        scan_registry_tags.each { |t| tags << t }
        tags
      end

      def law_pack_ids
        ids = Set.new
        begin
          require_relative "../../law/definition" unless defined?(::Law)
          ::Law.load_all if ::Law.respond_to?(:load_all)
          ::Law.definitions.each_key { |k| ids << k.to_s } if defined?(::Law) && ::Law.respond_to?(:definitions)
        rescue Exception
          nil
        end
        ids
      end

      def scan_registry_ids
        ids = Set.new
        begin
          return ids unless File.file?(File.expand_path("../review/scan/law.rb", __dir__))

          require_relative "../review/scan/law_dsl"

          Master::Review::Scan::Law.registry.each do |klass|
            decl = klass.respond_to?(:declaration) ? klass.declaration : nil
            ids << decl[:id].to_s if decl && decl[:id]
          end
        rescue Exception
          nil
        end
        ids
      end

      def scan_registry_tags
        tags = Set.new
        begin
          require_relative "../review/scan/law_dsl"
          Master::Review::Scan::Law.registry.each do |klass|
            # A LawDSL class carries its tags on the class; a declare-style one in its declaration.
            Array(klass.dsl_tags).each { |tag| tags << tag.to_s.upcase }
            decl = klass.respond_to?(:declaration) ? klass.declaration : nil
            Array(decl && decl[:law_tags]).each { |tag| tags << tag.to_s.upcase }
          end
        rescue Exception
          nil
        end
        tags
      end

      def law_define_ids_from_source
        ids = Set.new
        dir = File.expand_path("../../law", __dir__)
        return ids unless File.directory?(dir)

        Dir.glob(File.join(dir, "*.rb")).each do |file|
          content = File.read(file, mode: "r:bom|utf-8", invalid: :replace, undef: :replace)
          content.each_line do |line|
            if (m = line.match(/Law\.define\(:(\w+)/))
              ids << m[1]
            end
          end
        rescue StandardError
          next
        end
        ids
      end
    end
  end
end
