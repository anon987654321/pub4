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

      def awareness(root: Master::ROOT) = spatial(root:).fetch("awareness", {})

      # True when the mic cannot be hearing MASTER: nothing playing or loading,
      # and the tail after the last sentence has passed. The terminal listens
      # only between utterances; the browser listens while it speaks, so this is
      # the gate every feed of "the user is speaking" goes through.
      def echo_safe?(playing:, loading: false, ms_since_tts_end: nil, root: Master::ROOT)
        return false if playing || loading

        tail = awareness(root:).fetch("echo_safe", {}).fetch("tts_tail_ms", 900)
        ms_since_tts_end.nil? || ms_since_tts_end >= tail
      end

      def mouth(root: Master::ROOT) = spatial(root:).fetch("mouth", {})

      # The viseme a letter makes, by the same rule the browser's setViseme uses:
      # a vowel is itself, a bilabial or labiodental closes the lips, any other
      # letter is the relaxed E.
      def viseme_for(char, root: Master::ROOT)
        letter = char.to_s.downcase
        return letter.upcase if %w[a e i o u].include?(letter)

        mouth(root:).fetch("closed_letters", "mbpfwv").include?(letter) && !letter.empty? ? "M" : "E"
      end

      # { "open" => 0..1, "wide" => -1..1 } for a viseme name.
      def mouth_shape(name, root: Master::ROOT)
        shapes = mouth(root:).fetch("shapes", {})
        shapes.fetch(name.to_s, shapes.fetch("neutral", { "open" => 0.0, "wide" => 0.0 }))
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
