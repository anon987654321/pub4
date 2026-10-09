# frozen_string_literal: true

require_relative "../design"

module Master
  module Face
    # One semantic contract for every MASTER surface. Browser code receives the
    # same block as MASTER_FACE_CONTRACT; Ruby consumers read it here instead
    # of growing their own copies of mode, prompt, or spatial constants.
    module Contract
      module_function

      def data(root: Master::ROOT)
        Master.load_yaml(File.join(root, "data", "laws.yml"), default: {})
          .fetch("tokens", {})
          .fetch("face_interface", {})
      end

      def prompt(root: Master::ROOT) = data(root:).fetch("prompt", {})
      def state(root: Master::ROOT) = data(root:).fetch("state", {})
      def spatial(root: Master::ROOT) = data(root:).fetch("spatial", {})

      def prompt_measure(root: Master::ROOT)
        prompt(root:).fetch("measure_ch", Master::Design::Thresholds.measure_ideal_ch(root:))
      end

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

      def user_token(root: Master::ROOT) = prompt(root:).fetch("user_token", "$")
      def master_token(root: Master::ROOT) = prompt(root:).fetch("master_token", "master$")

      def modes(root: Master::ROOT)
        Array(state(root:).fetch("modes", [])).map(&:to_s).freeze
      end
    end
  end
end
