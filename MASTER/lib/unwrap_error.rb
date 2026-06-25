# frozen_string_literal: true

module Master
  # Raised when #value! is called on an Err result.
  class UnwrapError < RuntimeError; end

  # Pure Ruby reader + detector for phantom_recovery (data/rules.yml).
  module PhantomRecovery
    REPETITION_SPAN = 60
    REPETITION_MIN = 3

    module_function

    def detectors
      @detectors ||= begin
        data = Master.load_yaml(Master::RULES_PATH)
        (data.dig("phantom_recovery", "detectors") || {}).transform_values { |v| compile_detector(v) }
      end
    rescue StandardError
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
      bus&.publish("phantom:detected", patterns: hits, recovery: recovery)
      { patterns: hits, recovery: recovery }
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