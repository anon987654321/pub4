# frozen_string_literal: true

module Master
  module Ground
  # Loads and exposes rules, axioms, voice, and workflow from data/*.yml.
    class Rules
      include RuleAccessors
      include RulePromptBlocks

      RULES_SUBDIR = "rules"
      DATA_ALIASES = {
        workflow: %w[limits workflow],
        ruby_style: %w[style ruby_style],
        standing_orders: %w[state standing_orders],
      }.freeze

      def initialize(root: nil)
        @root = root || Master::ROOT
        @data_dir = File.join(@root, "data")
        @rules_path = File.join(@data_dir, "rules.yml")
        @soul_path = File.join(@data_dir, "soul.yml")
        @voice_path = Master.data_file("voice.yml")
        @data = load_yaml(@rules_path) || {}
        @voice_data = load_yaml(@voice_path) || {}
        @data["rules"] = load_split_rules
        @soul_data = load_yaml(@soul_path) || {}
        # limits.yml is no longer parsed here. It was loaded on every Rules
        # construction purely to back two accessors nobody called; the callers that
        # do want it (scan_request, fix_loop, mode_posture) each read it themselves,
        # mtime-cached. `data(:workflow)` still resolves it through DATA_ALIASES.
        @cache = {}
      end

      # mtime-aware cache. Reloads automatically when data/<name>.yml changes on disk.
      def data(name)
        key = name.to_sym
        path = resolve_data_path(key)
        return @cache[key]&.first || folded(key) unless path && File.exist?(path)

        mtime = File.mtime(path)
        cached = @cache[key]
        return cached.first if cached && cached.last >= mtime

        payload = without_schema(Master.load_yaml(path) || {})
        @cache[key] = [payload, mtime]
        payload
      end

      def kernel
        @kernel ||= begin
          all_rules = Master.flatten_rules(@data["rules"])
          all_rules
            .select { |r| r["tier"] == "kernel" }
            .each_with_object({}) { |r, h| h[r["id"]] = r["name"] }
            .freeze
        end
      end

      def philosophy(limit: nil)
        @philosophy ||= begin
          all_rules = Master.flatten_rules(@data["rules"])
          all_rules
            .reject { |r| r["tier"] == "kernel" }
            .map { |h| h.transform_keys(&:to_s) }
            .freeze
        end
        limit ? @philosophy.first(limit) : @philosophy
      end

      def all_rules = @all_rules ||= Master.flatten_rules(@data["rules"]).freeze
      def rules_for_scope(scope) = (@data.dig("rules", scope.to_s) || []).freeze

      def lookup(id)
        id_str = id.to_s
        kernel[id_str] || philosophy.find { |a| a["id"] == id_str }&.dig("name")
      end

      def valid_id?(id) = all_ids.include?(id.to_s)
      def all_ids = @all_ids ||= all_rules.map { |r| r["id"] }.compact.to_set.freeze
      def empty? = @data.empty?

      private

      # A section of rules.yml answers to its own stem, so a call site may ask
      # for :style or :design_rules without knowing they share a file. A stem
      # with no section returns {}, the same as an absent optional file.
      def folded(key)
        stems = DATA_ALIASES.fetch(key, [key.to_s])
        stems.filter_map { |stem| @data[stem] }.first || {}
      end

      def resolve_data_path(key)
        stems = DATA_ALIASES.fetch(key, [key.to_s])
        stems.map { |stem| File.join(@data_dir, "#{stem}.yml") }.find { |candidate| File.exist?(candidate) }
      end

      def load_split_rules
        dir = File.join(@data_dir, RULES_SUBDIR)
        return @data["rules"] || {} unless File.directory?(dir)
        Dir.glob(File.join(dir, "*.yml")).sort.each_with_object({}) do |f, merged|
          data = load_yaml(f) || {}
          data.each { |scope, rules| (merged[scope] ||= []).concat(Array(rules)) }
        end
      end

      def load_yaml(path)
        return unless File.exist?(path)
        Master.load_yaml(path)
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "rules.load_yaml", path:)
        nil
      end

      def without_schema(payload)
        return payload unless payload.is_a?(Hash) && payload.key?("schema")

        payload.reject { |key, _value| key == "schema" }
      end

    end
  end
end
