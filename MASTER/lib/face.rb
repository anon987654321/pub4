# frozen_string_literal: true

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
      # its last segments when it must be shortened.
      def shell_prompt(path: Master.repo_root, host: Socket.gethostname, root: Master::ROOT)
        name = host.to_s.split(".").first.to_s
        name = "openbsd" if name.empty?
        home = Dir.home
        dir = path.to_s == home ? "~" : path.to_s.sub(%r{\A#{Regexp.escape(home)}/}, "~/")
        budget = [prompt_max(root:) - name.length - 3, 1].max
        dir = "~/.../#{dir.split('/').last(2).join('/')}" if dir.length > budget && dir.count("/") > 2
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

      # Point-sprite sizing is shared with the browser shader through the same
      # canonical face_interface block; callers must not copy these dials.
      def stipple_point_size(root: Master::ROOT)
        data(root:).fetch("stipple", {}).fetch("point_size", {}).transform_keys(&:to_s).freeze
      end

      def modes(root: Master::ROOT)
        Array(state(root:).fetch("modes", [])).map(&:to_s).freeze
      end
    end
  end
end

require_relative "face/law_field"
