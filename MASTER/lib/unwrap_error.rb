# frozen_string_literal: true

module Master
  # Raised when #value! is called on an Err result.
  class UnwrapError < RuntimeError; end

  # Pure Ruby reader + detector for phantom_recovery (data/rules.yml).
  # Converts the aspirational detectors + "publish phantom:detected" into runtime.
  # Used by autoloop/pipeline for gaslighting/repetition/bad-XML recovery.
  module PhantomRecovery
    module_function

    def detectors
      @detectors ||= begin
        data = Master.load_yaml(Master::RULES_PATH)
        (data.dig("phantom_recovery", "detectors") || {}).transform_values { |v| v.is_a?(String) ? Regexp.new(v, Regexp::IGNORECASE) : v }
      end
    rescue
      {}
    end

    def detect(text, bus: nil)
      t = text.to_s
      hits = detectors.filter_map { |name, pat| name if pat.is_a?(Regexp) ? t.match?(pat) : false }
      return nil if hits.empty?
      bus&.publish("phantom:detected", patterns: hits, sample: t[0, 120])
      { patterns: hits, recovery: (Master.load_yaml(Master::RULES_PATH).dig("phantom_recovery", "recovery") || []) }
    end
  end
end
