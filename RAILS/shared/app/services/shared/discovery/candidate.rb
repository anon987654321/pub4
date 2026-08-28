# frozen_string_literal: true

module Shared
  module Discovery
    # One thing a provider offers, with the reason it is being offered.
    #
    # `reason` is a translation key rather than a sentence. The apps default
    # to Norwegian and assert through I18n keys, so a provider that returned
    # English prose would be both untranslatable and untestable.
    Candidate = Struct.new(:record, :reason_key, :score, :source, keyword_init: true) do
      def initialize(record:, reason_key:, score: 0.0, source: nil)
        super(record:, reason_key:, score: score.to_f, source: source&.to_sym)
      end

      def valid? = !record.nil? && !reason_key.to_s.empty?
    end
  end
end
