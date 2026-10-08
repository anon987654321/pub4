# frozen_string_literal: true

module Master
  module Review
    class Modes
      SUPPORTED = %w[direct react rewoo code_agent fix_hygiene repeat self_aware rival style].freeze

      def initialize(root: Master::ROOT)
        @root = root
      end

      def supported = SUPPORTED

      def wrap(message, mode: "direct")
        selected = SUPPORTED.include?(mode.to_s) ? mode.to_s : "direct"
        prompt = load_prompt(selected)
        format(prompt.fetch("template", "%{message}"), message: message.to_s)
      rescue StandardError => e
        Master::Trace::Dmesg.status("mode0", "wrap failed, #{mode}, #{e.class}: #{e.message}")
        message.to_s
      end

      private

      def load_prompt(mode)
        # One prompts.yml keyed by mode — was four mode_<name>.yml files whose
        # only reader interpolated the filename, which no grep could follow.
        path = File.join(@root, "data", "prompts.yml")
        (Master.load_yaml(path) || {})[mode.to_s] || {}
      end
    end
  end
end
