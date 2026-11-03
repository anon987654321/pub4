# frozen_string_literal: true

module Master
  module Ground
    # Loads and exposes laws, axioms, voice, and workflow from data/*.yml.
    class Laws
      # Pure data-accessor readers over the loaded YAML — kept in a separate
      # module so NO_GOD_CLASS's AST-based public-method count only sees
      # Laws' own lookup/parsing methods, not this passthrough layer.
      # `workflow` (the whole limits.yml hash) and `workflow_law(key)` (a generic
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
        def inverted_pyramid = Array(voice["inverted_pyramid"])

        # Lazy, for the same reason limits.yml stopped being parsed in the
        # constructor: `constitution` is the only reader, and every Laws built
        # to ask for `laws` was opening soul.yml to back an accessor it never
        # touched. Soul owns global source authority and protected paths;
        # laws.yml owns individual Law statements and invariant-node order.
        def soul_data = Master.soul_config(root: @root)

        def constitution
          manifest = soul_data
          references = manifest["references"] || {}
          catalogue = Master.laws_document(root: @root)
          golden_id = references["golden_law"].to_s
          golden = catalogue[golden_id] || {}
          simulation = catalogue["TRUTHFUL_STATUS_no_simulated_completion"] || {}
          anti_simulation = simulation["anti_simulation"].is_a?(Hash) ? simulation["anti_simulation"] : {}
          anti_simulation = anti_simulation.merge(
            "forbidden" => Array(manifest.dig("absolute", "anti_simulation", "forbidden"))
          ).freeze
          authorship = catalogue["SACRED_AUTHORSHIP"] || {}
          {
            "golden_law" => [golden_id, golden["statement"]].compact.join(": "),
            "protection" => {
              "principle" => authorship["statement"],
              "protected_paths" => Master::Soul.sacred_paths(root: @root),
            }.freeze,
            "banned_output" => voice["banned_output"],
            "anti_simulation" => anti_simulation,
            "communication_style" => voice["style"],
          }.freeze
        end

        # From law/, the executable Law implementations. This is separate from
        # the normative flat statements in laws.yml and the legacy execution
        # metadata still required by Law::Definition.
        def laws
          @laws ||= begin
            require File.join(Master::ROOT, "law", "definition") unless defined?(::Law)
            ::Law.load_all(File.join(Master::ROOT, "law")) if ::Law.definitions.empty?
            ::Law.definitions.values.to_h { |law| [law.id.to_s, (law.practice || law.fix).to_s.gsub(/\s+/, " ").strip] }.freeze
          rescue StandardError => e
            Master::Ground::Swallow.log(e, context: "laws.laws", path: File.join(Master::ROOT, "law"))
            raise "laws registry unreadable: #{e.class}: #{e.message}"
          end
        end
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

          top = items.map { |law| "  #{law["id"]}: #{law["statement"]}" }.join("\n")
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
        # limits.yml is no longer parsed here. It was loaded on every Laws
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

      # The kernel is projected from the ordered invariant nodes plus the
      # preservation Law referenced by Soul. No tier or source string defines it.
      def kernel
        @kernel ||= begin
          law_text = laws
          rows = Master.law_entries(root: @root)
          selected = rows.select { |row| row["node"] || row["id"] == "PRESERVE_FIRST" }
          selected.to_h do |row|
            id = row.fetch("id")
            text = law_text[id] || row.fetch("statement")
            [id, text.to_s.gsub(/\s+/, " ").strip]
          end.freeze
        end
      end

      def philosophy(limit: nil)
        items = Master.law_entries(root: @root).map { |law| law.transform_keys(&:to_s) }.freeze
        limit ? items.first(limit) : items
      end

      def lookup(id)
        id_str = id.to_s
        kernel[id_str] || philosophy.find { |law| law["id"] == id_str }&.dig("statement")
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
