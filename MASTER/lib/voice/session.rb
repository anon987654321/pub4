# frozen_string_literal: true

require "monitor"
require_relative "speech"
require_relative "playback"

module Master
  module Voice
    # One conversational voice session. Session owns turn state; Speech remains
    # synthesis policy and Playback remains the audio cancellation boundary.
    class Session
      STATES = %i[listening thinking speaking interrupted].freeze

      attr_reader :state, :generation

      def initialize
        @lock = Monitor.new
        @state = :listening
        @generation = 0
      end

      def listening!
        transition!(:listening)
      end

      def thinking!
        transition!(:thinking)
      end

      def speaking!
        begin_turn!(:speaking)
      end

      def speak(text, **options)
        value = text.to_s.strip
        return false if value.empty?

        token = begin_turn!(:speaking)
        parts = Speech.chunks(value)
        parts = [value] if parts.empty?

        parts.each_with_index do |part, index|
          break unless active?(token)

          Playback.enqueue(
            part,
            generation: token,
            voice: options[:voice],
            style: options[:style],
            rate: options[:rate],
            pitch: options[:pitch],
            last: index == parts.length - 1,
          )
        end
        true
      end

      # Called by speech/VAD input as soon as the user takes the floor.
      # Playback owns the cancellation generation so queued and in-flight work
      # cannot re-enter the speaker after an interruption.
      def interrupt!(reason: :user_speech)
        token = Playback.interrupt!(reason)
        @lock.synchronize do
          @generation = token
          @state = :interrupted
        end
        token
      end

      def active?(token)
        @lock.synchronize { token == @generation && @state != :interrupted } &&
          Playback.generation_active?(token)
      end

      def begin_turn!(state)
        state = state.to_sym
        raise ArgumentError, "unknown voice state: #{state}" unless STATES.include?(state)

        token = if state == :speaking
                  Playback.begin_generation!
                else
                  @lock.synchronize { @generation }
                end
        @lock.synchronize do
          @generation = token
          @state = state
        end
        token
      end

      private

      def transition!(next_state)
        state = next_state.to_sym
        raise ArgumentError, "unknown voice state: #{state}" unless STATES.include?(state)

        @lock.synchronize { @state = state }
      end
    end
  end
end
