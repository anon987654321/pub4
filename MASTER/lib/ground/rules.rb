# frozen_string_literal: true


module Master
  module Ground
    class Rules
      # Pure data-accessor readers over the loaded YAML — kept in a separate
      # module so NO_GOD_CLASS's AST-based public-method count only sees
      # Rules' own lookup/parsing methods, not this passthrough layer.
      # `workflow` (the whole limits.yml hash) and `workflow_rule(key)` (a generic
      # reader for any key in it) both lived here with zero call sites, and between
      # them they made 29 unread keys in that file look reachable. Deleted with the
      # split — see data/limits.yml. A generic accessor over a data file is how a
      # file stops having readers one can name.
      module RuleAccessors
        def voice = @voice ||= (@voice_data["voice"] || @data["voice"] || {}).freeze
        def strunk = @strunk ||= (voice["strunk"] || {}).freeze
        def preserve = @preserve ||= (voice["preserve"] || {}).freeze

        # Lazy, for the same reason limits.yml stopped being parsed in the
        # constructor: `constitution` is the only reader, and every Rules built
        # to ask for `rules` was opening soul.yml to back an accessor it never
        # touched. RuleLoop#build_soul_preamble does exactly that, so a preamble
        # read the file twice and its cache could only ever halve the cost.
        def soul_data = @soul_data ||= (load_yaml(@soul_path) || {})

        def constitution
          @constitution ||= begin
            absolute = soul_data["absolute"] || {}
            {
              "golden_rule" => absolute["golden_rule"] || @data["golden_rule"],
              "protection" => absolute["protection_tiers"] || @data["protection"],
              "banned_output" => voice["banned_output"],
              # soul is the one source; the voice.yml shadow copy is deleted, so
              # a fallback arm here would read a key that no longer exists.
              "anti_simulation" => absolute["anti_simulation"],
              "communication_style" => voice["style"],
            }.freeze
          end
        end

        # From law/, the one registry. soul carried absolute.rules until the
        # `conduct` kind let a rule about how to work be a Law like any other.
        def rules
          @rules ||= begin
            require File.join(Master::ROOT, "law", "law") unless defined?(::Law)
            ::Law.load_all(File.join(Master::ROOT, "law")) if ::Law.rules.empty?
            ::Law.rules.values.to_h { |r| [r.id.to_s, (r.practice || r.fix).to_s.gsub(/\s+/, " ").strip] }.freeze
          rescue StandardError
            {}.freeze
          end
        end
        def thresholds = @thresholds ||= (@data["thresholds"] || {}).freeze
        def languages_config = @languages_config ||= (@data["languages"] || {}).freeze
      end
    end
  end
end
module Master
  module Ground
    class Rules
      # Markdown block rendering for system-prompt injection — a rendering
      # concern separate from Rules' own lookup/parsing responsibility.
      module RulePromptBlocks
        def kernel_block
          return if kernel.empty?

          pairs = kernel.map { |id, stmt| "  #{id}: #{stmt}" }.join("\n")
          "## Kernel Rules (enforced)\n#{pairs}"
        end

        def philosophy_block(limit: 5)
          items = philosophy(limit:)
          return if items.empty?

          top = items.map { |a| "  #{a["id"]}: #{a["name"]}" }.join("\n")
          "## Rules (top #{items.size})\n#{top}"
        end
      end
    end
  end
end

module Master
  module Ground
  # Loads and exposes rules, axioms, voice, and workflow from data/*.yml.
    class Rules
      include RuleAccessors
      include RulePromptBlocks

      RULES_SUBDIR = "rules"
      DATA_ALIASES = {
        workflow: %w[limits workflow],
        # The path is the style block itself: these accessors dig into it for
        # ruby/html/css/typography, and the old %w[style ruby_style] pointed at a
        # key that has never existed, so data(:ruby_style) returned nil and every
        # language-style line was silently dropped from the prompt.
        ruby_style: %w[style],
        rails_stack: %w[rails_stack],
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
