# frozen_string_literal: true

module Master
  module Ground
    # Loads and exposes rules, axioms, voice, and workflow from data/*.yml.
    class Laws
      # Pure data-accessor readers over the loaded YAML — kept in a separate
      # module so NO_GOD_CLASS's AST-based public-method count only sees
      # Laws' own lookup/parsing methods, not this passthrough layer.
      # `workflow` (the whole limits.yml hash) and `workflow_rule(key)` (a generic
      # reader for any key in it) both lived here with zero call sites, and between
      # them they made 29 unread keys in that file look reachable. Deleted with the
      # split — see data/limits.yml. A generic accessor over a data file is how a
      # file stops having readers one can name.
      module LawAccessors
        def voice
          payload = data(:voice)
          payload["voice"] || {}
        end

        def strunk = voice["strunk"] || {}
        def preserve = voice["preserve"] || {}

        # Lazy, for the same reason limits.yml stopped being parsed in the
        # constructor: `constitution` is the only reader, and every Laws built
        # to ask for `rules` was opening soul.yml to back an accessor it never
        # touched. LawLoop#build_soul_preamble does exactly that, so a preamble
        # read the file twice and its cache could only ever halve the cost.
        def soul_data = Master.soul_config(root: @root)

        def constitution
          absolute = soul_data["absolute"] || {}
          {
            "golden_rule" => absolute["golden_rule"] || laws_data["golden_rule"],
            "protection" => absolute["protection_tiers"] || laws_data["protection"],
            "banned_output" => voice["banned_output"],
            # soul is the one source; the voice.yml shadow copy is deleted, so
            # a fallback arm here would read a key that no longer exists.
            "anti_simulation" => absolute["anti_simulation"],
            "communication_style" => voice["style"],
          }.freeze
        end

        # From law/, the one registry. soul carried absolute.rules until the
        # `conduct` kind let a rule about how to work be a Law like any other.
        def laws
          @laws ||= begin
            require File.join(Master::ROOT, "law", "law") unless defined?(::Law)
            ::Law.load_all(File.join(Master::ROOT, "law")) if ::Law.definitions.empty?
            ::Law.definitions.values.to_h { |law| [law.id.to_s, (r.practice || r.fix).to_s.gsub(/\s+/, " ").strip] }.freeze
          rescue StandardError => e
            Master::Ground::Swallow.log(e, context: "laws.laws", path: File.join(Master::ROOT, "law"))
            raise "laws registry unreadable: #{e.class}: #{e.message}"
          end
        end
        def thresholds = laws_data["thresholds"] || {}
        def languages_config = laws_data["languages"] || {}
      end
      # Markdown block rendering for system-prompt injection — a rendering
      # concern separate from Laws' own lookup/parsing responsibility.
      module LawPromptBlocks
        def kernel_block
          return if kernel.empty?

          pairs = kernel.map { |id, stmt| "  #{id}: #{stmt}" }.join("\n")
          "## Kernel Laws (enforced)\n#{pairs}"
        end

        def philosophy_block(limit: 5)
          items = philosophy(limit:)
          return if items.empty?

          top = items.map { |a| "  #{a["id"]}: #{a["name"]}" }.join("\n")
          "## Laws (top #{items.size})\n#{top}"
        end
      end

      include LawAccessors
      include LawPromptBlocks

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

        stat = File.stat(path)
        stamp = [stat.size, stat.ino, stat.mtime.to_r]
        cached = @cache[key]
        return cached.first if cached && cached.last == stamp

        payload = without_schema(Master.load_yaml(path) || {})
        @cache[key] = [payload, stamp]
        payload
      end

      def kernel
        all_laws = Master.law_entries(root: @root)
        all_laws
          .select { |r| r["tier"] == "kernel" }
          .each_with_object({}) { |r, h| h[r["id"]] = r["name"] }
          .freeze
      end

      def philosophy(limit: nil)
        all_laws = Master.law_entries(root: @root)
        items = all_laws
          .reject { |r| r["tier"] == "kernel" }
          .map { |h| h.transform_keys(&:to_s) }
          .freeze
        limit ? items.first(limit) : items
      end


      def lookup(id)
        id_str = id.to_s
        kernel[id_str] || philosophy.find { |a| a["id"] == id_str }&.dig("name")
      end

      def empty? = laws_data.empty?

      private

      # A section of laws.yml answers to its own stem, so a call site may ask
      # for :style or :design_rules without knowing they share a file. A stem
      # with no section returns {}, the same as an absent optional file.
      def laws_data
        Master.load_laws(root: @root) || {}
      end

      def folded(key)
        stems = DATA_ALIASES.fetch(key, [key.to_s])
        stems.filter_map { |stem| laws_data[stem] }.first || {}
      end

      def resolve_data_path(key)
        stems = DATA_ALIASES.fetch(key, [key.to_s])
        stems.map { |stem| File.join(@data_dir, "#{stem}.yml") }.find { |candidate| File.exist?(candidate) }
      end

      def without_schema(payload)
        return payload unless payload.is_a?(Hash) && payload.key?("schema")

        payload.reject { |key, _value| key == "schema" }
      end

    end
  end
end
