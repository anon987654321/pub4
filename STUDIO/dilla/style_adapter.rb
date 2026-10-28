# frozen_string_literal: true

require "digest"

module Dilla
  # Adapter boundary for symbolic proposals. This module validates artifacts;
  # it does not load or execute the DSP monolith and never renders audio itself.
  module StyleAdapter
    REQUIRED_ABC_HEADERS = %w[X: T: M: L: K:].freeze

    def self.validate_abc!(abc, validator: nil, negative_list: [], matcher: nil)
      text = abc.to_s
      raise ArgumentError, "ABC score is empty" if text.strip.empty?
      missing = REQUIRED_ABC_HEADERS.reject { |header| text.lines.any? { |line| line.start_with?(header) } }
      raise ArgumentError, "invalid ABC score; missing #{missing.join(', ')}" unless missing.empty?
      raise ArgumentError, "ABC validator must be supplied by the engine" unless validator.respond_to?(:call)
      errors = Array(validator.call(text))
      raise ArgumentError, "ABC validation failed: #{errors.join('; ')}" unless errors.empty?
      unless Array(negative_list).empty?
        raise ArgumentError, "negative-list matcher required" unless matcher.respond_to?(:call)
        hit = Array(negative_list).find { |item| matcher.call(text, item) }
        raise Refused, "STYLE_REFUSAL: #{hit}" if hit
      end
      { status: :ready, abc: text, sha256: Digest::SHA256.hexdigest(text) }
    end

    def self.validate_mix_parameters!(tracks)
      raise ArgumentError, "mix parameters must be a track map" unless tracks.is_a?(Hash) && !tracks.empty?
      tracks.each do |track, params|
        raise ArgumentError, "track #{track} parameters must be a map" unless params.is_a?(Hash)
        if params.key?(:gain_db) && !(-60.0..24.0).cover?(Float(params[:gain_db]))
          raise ArgumentError, "track #{track} gain_db out of range"
        end
        if params.key?(:pan) && !(-1.0..1.0).cover?(Float(params[:pan]))
          raise ArgumentError, "track #{track} pan out of range"
        end
      end
      { status: :ready, tracks: tracks }
    end

    class Refused < ArgumentError; end
    private_constant :REQUIRED_ABC_HEADERS
  end
end
