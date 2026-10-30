# frozen_string_literal: true

require "digest"
require "json"
require_relative "design"

module Master
  module Face
    # One semantic contract for every MASTER surface. Browser code receives the
    # same block as MASTER_FACE_CONTRACT; Ruby consumers read it here instead
    # of growing their own copies of mode, prompt, or spatial constants.
    module Contract
      module_function

      def data(root: Master::ROOT)
        Master.tokens(root:).fetch("face_interface", {})
      end

      def prompt(root: Master::ROOT) = data(root:).fetch("prompt", {})
      def state(root: Master::ROOT) = data(root:).fetch("state", {})
      def spatial(root: Master::ROOT) = data(root:).fetch("spatial", {})

      def prompt_measure(root: Master::ROOT)
        prompt(root:).fetch("measure_ch", Master::Design::Thresholds.measure_ideal_ch(root:))
      end

      # The plain-ASCII renderer's tunables; the terminal and the web face both read them.
      def ascii(root: Master::ROOT) = data(root:).fetch("ascii", {})

      # The prompt glyphs: :input, :continuation or :output.
      def glyph(name, root: Master::ROOT) = ascii(root:).fetch("prompt", {}).fetch(name.to_s)

      def budget(root: Master::ROOT) = spatial(root:).fetch("budget", {})
      def camera(root: Master::ROOT) = spatial(root:).fetch("camera", {})
      def layers(root: Master::ROOT)
        Array(spatial(root:).fetch("layers", [])).map(&:to_s).freeze
      end

      def mode_aliases(root: Master::ROOT)
        aliases = state(root:).fetch("mode_aliases", data(root:).fetch("mode_aliases", {}))
        (aliases || {}).transform_keys(&:to_s).transform_values(&:to_s).freeze
      end

      def prompt_max(root: Master::ROOT)
        prompt(root:).fetch("max_ch", 72)
      end

      # The OpenBSD Operator prompt, host:path$, e.g. vm23:~/pub4$. One shape
      # for the terminal and the web face; the path is home-relative and keeps
      # its last segments when it must be shortened. Comfort scales the same
      # way a shell's does: the host is its first name, and a deep path
      # narrows to where you are standing rather than reciting the road.
      HOST_MAX = 8
      PATH_SOFT_MAX = 24

      def shell_prompt(path: Master.repo_root, host: Socket.gethostname, root: Master::ROOT)
        name = host.to_s.split(".").first.to_s.split("-").first.to_s[0, HOST_MAX]
        name = "openbsd" if name.empty?
        home = Dir.home
        dir = path.to_s == home ? "~" : path.to_s.sub(%r{\A#{Regexp.escape(home)}/}, "~/")
        budget = [prompt_max(root:) - name.length - 3, 1].max
        if dir.length > PATH_SOFT_MAX && dir.count("/") > 2
          dir = "~/.../#{dir.split('/').last(2).join('/')}"
        end
        dir = dir[-budget, budget] if dir.length > budget
        "#{name}:#{dir}$"
      end

      def user_token(root: Master::ROOT) = prompt(root:).fetch("user_token", "user")
      def master_token(root: Master::ROOT) = prompt(root:).fetch("master_token", "master")

      # The stipple dials for one mode; an unknown mode reads as idle, as the web face does.
      def stipple_profile(mode, root: Master::ROOT)
        profiles = data(root:).fetch("stipple", {}).fetch("profiles", {})
        profiles.fetch(mode.to_s) { profiles.fetch("idle") }.transform_keys(&:to_s).freeze
      end

      # What a state means in the stipple material: its membership, its force and a note.
      # An unknown mode reads as idle, as the dials do.
      def stipple_meaning(mode, root: Master::ROOT)
        face = data(root:)
        name = face.fetch("stipple_force", {}).key?(mode.to_s) ? mode.to_s : "idle"
        { "membership" => face.fetch("stipple_membership", {}).fetch(name),
          "force" => face.fetch("stipple_force", {}).fetch(name),
          "note" => face.fetch("stipple_note", {}).fetch(name) }.freeze
      end

      # The one-pixel sprite's camera-depth brightness response is shared with
      # the browser shader through this canonical contract.
      def stipple_depth_response(root: Master::ROOT)
        data(root:).fetch("stipple", {}).fetch("depth_response", {}).transform_keys(&:to_s).freeze
      end

      def modes(root: Master::ROOT)
        Array(state(root:).fetch("modes", [])).map(&:to_s).freeze
      end
    end

    # A glyph is a view of a ranked law, never a parallel list of principles.
    module LawField
      MAX_CACHE_ENTRIES = 4
      @mutex = Mutex.new
      @cache = {}

      module_function

      def config(root: Master::ROOT)
        catalog(root:).fetch("face_ascii", {})
      end

      def laws(root: Master::ROOT)
        settings = config(root:)
        glyphs = Array(settings.fetch("law_glyphs", []))
        limit = Integer(settings.fetch("max_laws", 8)).clamp(0, glyphs.size)

        with_glyphs(ranked_laws(catalog(root:)).first(limit), glyphs)
      end

      def with_glyphs(rows, glyphs)
        rows.each_with_index.map { |row, index| row.merge("glyph" => glyphs.fetch(index)) }
      end

      def ranked_laws(catalog)
        rows = catalog.filter_map do |id, row|
          next unless row.is_a?(Hash) && row["priority"].is_a?(Numeric)
          next if row["statement"].to_s.empty?

          { "id" => id.to_s, "priority" => row.fetch("priority"), "statement" => row.fetch("statement").to_s }
        end
        rows.sort_by { |row| [row.fetch("priority"), row.fetch("id")] }
      end

      def browser_payload(root: Master::ROOT)
        rows = laws(root:)
        settings = config(root:)

        {
          schema: 1,
          laws: rows,
          digest: Digest::SHA256.hexdigest(JSON.generate(rows)),
          toggle_key: settings.fetch("web_law_toggle_key", "l"),
          overlay_toggle_key: settings.fetch("web_toggle_key", "v"),
          enabled: settings.fetch("web_overlay", true),
        }
      end

      def catalog(root: Master::ROOT)
        root = Master.master_root(root:)
        path = File.join(root, "data", "laws.yml")
        stat = File.stat(path)
        key = [path, stat.size, stat.ino, stat.mtime.to_r]
        @mutex.synchronize do
          return @cache.fetch(key) if @cache.key?(key)

          @cache.clear if @cache.size >= MAX_CACHE_ENTRIES
          @cache[key] = Master.load_laws(root:) || {}
        end
      end
    end
  end
end
