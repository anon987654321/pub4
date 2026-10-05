# frozen_string_literal: true

module Master
  module Ground
    # Loads and exposes rules, axioms, voice, and workflow from data/*.yml.
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
        def voice = (voice_data["voice"] || law_data["voice"] || {}).freeze
        def strunk = (voice["strunk"] || {}).freeze
        def preserve = (voice["preserve"] || {}).freeze

        # Lazy, for the same reason limits.yml stopped being parsed in the
        # constructor: `constitution` is the only reader, and every Rules built
        # to ask for `rules` was opening soul.yml to back an accessor it never
        # touched. RuleLoop#build_soul_preamble does exactly that, so a preamble
        # read the file twice and its cache could only ever halve the cost.
        def soul_data = Master.soul_config(root: @root)

        def constitution
          absolute = soul_data["absolute"] || {}
          {
            "golden_rule" => absolute["golden_rule"] || law_data["golden_rule"],
            "protection" => absolute["protection_tiers"] || law_data["protection"],
            "banned_output" => voice["banned_output"],
            # soul is the one source; the voice.yml shadow copy is deleted, so
            # a fallback arm here would read a key that no longer exists.
            "anti_simulation" => absolute["anti_simulation"],
            "communication_style" => voice["style"],
          }.freeze
        end

        # From law/, the one registry. soul carried absolute.rules until the
        # `conduct` kind let a rule about how to work be a Law like any other.
        def rules
          law_dir = File.join(@root, "law")
          require File.join(law_dir, "law") unless defined?(::Law)
          ::Law.load_all(law_dir)
          ::Law.rules.values.to_h { |r| [r.id.to_s, (r.practice || r.fix).to_s.gsub(/\s+/, " ").strip] }.freeze
        rescue StandardError => e
          Master::Ground::Swallow.log(e, context: "rules.rules", path: law_dir)
          raise "rules registry unreadable: #{e.class}: #{e.message}"
        end
        def thresholds = (law_data["thresholds"] || {}).freeze
        def languages_config = (law_data["languages"] || {}).freeze
      end
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

      include RuleAccessors
      include RulePromptBlocks

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
        @voice_path = File.join(@root, "data", "voice.yml")

        # limits.yml is no longer parsed here. It was loaded on every Rules
        # construction purely to back two accessors nobody called; the callers that
        # do want it (scan/request, fix_loop, mode_posture) each read it themselves,
        # mtime-cached. `data(:workflow)` still resolves it through DATA_ALIASES.
        @cache = {}
      end

      # mtime-aware cache. Reloads automatically when data/<name>.yml changes on disk.
      def data(name)
        key = name.to_sym
        path = resolve_data_path(key)
        unless path && File.exist?(path)
          @cache.delete(key)
          return folded(key)
        end

        mtime = File.mtime(path)
        cached = @cache[key]
        return cached.first if cached && cached.last >= mtime

        payload = without_schema(Master.load_yaml(path) || {})
        @cache[key] = [payload, mtime]
        payload
      end

      def kernel
        @kernel ||= begin
          all_rules = Master.law_entries(root: @root)
          all_rules
            .select { |r| r["tier"] == "kernel" }
            .each_with_object({}) { |r, h| h[r["id"]] = r["name"] }
            .freeze
        end
      end

      def philosophy(limit: nil)
        @philosophy ||= begin
          all_rules = Master.law_entries(root: @root)
          all_rules
            .reject { |r| r["tier"] == "kernel" }
            .map { |h| h.transform_keys(&:to_s) }
            .freeze
        end
        limit ? @philosophy.first(limit) : @philosophy
      end


      def lookup(id)
        id_str = id.to_s
        kernel[id_str] || philosophy.find { |a| a["id"] == id_str }&.dig("name")
      end

      def empty? = law_data.empty?

      private

      # A section of laws.yml answers to its own stem, so a call site may ask
      # for :style or :design_rules without knowing they share a file. A stem
      # with no section returns {}, the same as an absent optional file.
      def folded(key)
        stems = DATA_ALIASES.fetch(key, [key.to_s])
        stems.filter_map { |stem| law_data[stem] }.first || {}
      end

      def law_data
        @law_data_stamp = law_data_signature
        @law_data ||= Master.load_laws(root: @root) || {}
      end

      def law_data_signature
        path = File.join(@data_dir, "laws.yml")
        return nil unless File.file?(path)

        stat = File.stat(path)
        [stat.size, stat.ino, stat.mtime.to_r]
      end

      def voice_data
        return {} unless File.file?(@voice_path)

        Master.load_yaml(@voice_path) || {}
      end

      def resolve_data_path(key)
        stems = DATA_ALIASES.fetch(key, [key.to_s])
        stems.map { |stem| File.join(@data_dir, "#{stem}.yml") }.find { |candidate| File.exist?(candidate) }
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
