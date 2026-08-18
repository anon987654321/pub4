# frozen_string_literal: true

module Master
  # Calling #value! on an Err result raises this.
  class UnwrapError < RuntimeError; end

  # Pure Ruby reader + detector for phantom_recovery (data/rules.yml).
  module PhantomRecovery
    REPETITION_SPAN = 60
    REPETITION_MIN = 3
    HALT_ON = 3

    @occurrences = Hash.new(0)
    @occurrence_mutex = Mutex.new

    module_function

    def detectors
      @detectors ||= begin
        data = Master.load_yaml(Master::RULES_PATH)
        (data.dig("phantom_recovery", "detectors") || {}).transform_values { |v| compile_detector(v) }
      end
    rescue StandardError => e
      Master::Ground::Swallow.log(e, context: "PhantomRecovery.detectors")
      {}
    end

    def detect(text, bus: nil)
      t = text.to_s
      hits = []
      detectors.each do |name, pattern|
        hits << name if pattern.is_a?(Regexp) && t.match?(pattern)
      end
      hits << "text_repetition_loop" if repetition_loop?(t)

      return if hits.empty?

      recovery = Master.load_yaml(Master::RULES_PATH).dig("phantom_recovery", "recovery") || []
      bus&.publish("phantom:detected", patterns: hits, recovery:)
      { patterns: hits, recovery: }
    end

    def handle(text, bus: nil, session: nil, scope: :default)
      finding = detect(text, bus:)
      unless finding
        # A clean response closes the episode, so the count below is consecutive
        # phantoms rather than every phantom this process has ever seen. That is
        # what the ladder needs to mean: data/rules.yml describes discard first,
        # escalate "on second occurrence", halt "on third", and a counter that
        # only rises reaches three once and then halts every phantom for the
        # life of the process — with gaslighting_preamble matching any reply
        # that opens "I can", "Let me" or "Sure,", which is most of them.
        reset!(scope:)
        return { action: :continue }
      end

      # A finding made only of style_only detectors is a working model writing
      # prose somebody dislikes, so it is reported and then left alone. Spending
      # the ladder on it halts the conversation over phrasing, and the style rule
      # already has four enforcers that correct rather than halt.
      if style_only?(finding[:patterns])
        reset!(scope:)
        return { action: :continue, **finding }
      end

      count = record_occurrence(scope)
      bus&.publish("phantom:occurrence", count:, scope:)
      recovery_response(count, finding, bus:, session:, scope:)
    end

    def style_only_detectors
      @style_only_detectors ||= begin
        data = Master.load_yaml(Master::RULES_PATH)
        Array(data.dig("phantom_recovery", "style_only")).map(&:to_s)
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "PhantomRecovery.style_only_detectors")
        []
      end
    end

    def style_only?(patterns)
      names = Array(patterns).map(&:to_s)
      return false if names.empty?

      (names - style_only_detectors).empty?
    end

    def record_occurrence(scope)
      @occurrence_mutex.synchronize do
        @occurrences[scope] += 1
        @occurrences[scope]
      end
    end

    def recovery_response(count, finding, bus:, session:, scope:)
      case count
      when 1
        session&.rollback_last_assistant_message if session.respond_to?(:rollback_last_assistant_message)
        bus&.publish("phantom:recovery", step: 1, action: "discard_last_response")
        { action: :discard, **finding }
      when 2
        bus&.publish("phantom:recovery", step: 2, action: "escalate_model_tier")
        { action: :escalate, **finding }
      else
        bus&.publish("phantom:halt", count:, scope:)
        { action: :halt, **finding }
      end
    end

    def reset!(scope: :default)
      @occurrence_mutex.synchronize { @occurrences.delete(scope) }
    end

    def repetition_loop?(text)
      normalized = text.gsub(/\s+/, " ")
      return false if normalized.length < REPETITION_SPAN * REPETITION_MIN

      counts = Hash.new(0)
      (0..(normalized.length - REPETITION_SPAN)).each do |index|
        span = normalized[index, REPETITION_SPAN]
        counts[span] += 1
        return true if counts[span] >= REPETITION_MIN
      end
      false
    end

    def compile_detector(value)
      return value unless value.is_a?(String)

      literal = value.match(%r{\A/(.*)/([imx]*)\z})
      return Regexp.new(value, Regexp::IGNORECASE) unless literal

      flags = literal[2].chars.reduce(0) do |opts, flag|
        opts | { "i" => Regexp::IGNORECASE, "m" => Regexp::MULTILINE, "x" => Regexp::EXTENDED }.fetch(flag, 0)
      end
      Regexp.new(literal[1], flags)
    end
  end
end
