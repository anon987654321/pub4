# frozen_string_literal: true

require "digest"
require "json"

module Master
  module Voice
    # Engine-agnostic spoken performance plan.
    #
    # Performance turns emotion into a continuous, bounded contour. It keeps
    # sentence boundaries as the synthesis contract, but reads clause markers
    # inside each sentence so punctuation can influence role, emphasis and rest.
    module Performance
      MAX_RATE_DELTA = 6
      MAX_PITCH_DELTA_HZ = 14
      MAX_RATE_STEP = 2
      MAX_PITCH_STEP_HZ = 5
      MIN_RATE = -12
      MAX_RATE = 10
      MIN_PITCH_HZ = -24
      MAX_PITCH_HZ = 24
      MIN_PAUSE_MS = 90
      MAX_PAUSE_MS = 480
      DEFAULT_PAUSE_MS = 145

      ROLE_RATE = {
        opening: 1,
        setup: 0,
        delivery: 1,
        parenthetical: -1,
        contrast: 1,
        reveal: 2,
        question: 0,
        warning: -1,
        list_item: 0,
        soft_landing: -1,
        closing: -2,
        body: 0,
      }.freeze

      ROLE_PITCH = {
        opening: 2,
        setup: 0,
        delivery: 3,
        parenthetical: -2,
        contrast: 2,
        reveal: 4,
        question: 5,
        warning: -4,
        list_item: 1,
        soft_landing: -2,
        closing: -2,
        body: 0,
      }.freeze

      module_function

      def plan(text, emotion: {}, style: :normal)
        phrases = text.to_s.split(/(?<=[.!?])\s+/).map(&:strip).reject(&:empty?)
        phrases = [text.to_s.strip] if phrases.empty?

        raw = phrases.each_with_index.map do |phrase, index|
          role = sentence_role(phrase, index, phrases.length)
          seed = Digest::SHA256.hexdigest(phrase)[0, 8].to_i(16)
          arousal = score(emotion, :arousal)
          valence = score(emotion, :valence)
          intimacy = score(emotion, :intimacy)
          expressiveness = score(emotion, :expressiveness)
          arc = arc_factor(index, phrases.length)

          rate = ROLE_RATE.fetch(role) +
                 ((arousal - 0.35) * 3.0).round +
                 (expressiveness * 1.5 * arc).round +
                 ((seed % 5) - 2)
          pitch = ROLE_PITCH.fetch(role) +
                  ((valence - 0.5) * 8.0).round -
                  (intimacy * 4.0).round +
                  ((seed % 7) - 3)
          rate, pitch = apply_emphasis(rate, pitch, emphasis_for(role, phrase))
          rate = rate.clamp(-MAX_RATE_DELTA, MAX_RATE_DELTA)
          pitch = pitch.clamp(-MAX_PITCH_DELTA_HZ, MAX_PITCH_DELTA_HZ)

          {
            text: phrase,
            role:,
            rate_delta: rate,
            pitch_delta_hz: pitch,
            pause_ms: pause_ms_for(role, index, phrases.length, emotion),
            emphasis: emphasis_for(role, phrase),
            style: style.to_sym,
          }
        end

        raw.each_with_index.map do |part, index|
          previous = raw[index - 1]
          next part unless previous

          part.merge(
            rate_delta: smooth_step(part[:rate_delta], previous[:rate_delta], MAX_RATE_STEP),
            pitch_delta_hz: smooth_step(part[:pitch_delta_hz], previous[:pitch_delta_hz], MAX_PITCH_STEP_HZ),
          )
        end
      end

      # One timeline for synthesis metadata, the event bus and Face.
      # Durations are estimates and the browser normalizes them to real audio,
      # so every visual consumer follows the audio clock rather than wall time.
      def timeline(text, emotion: {}, style: :normal, rate: nil, pitch: nil, voice: nil)
        clean = text.to_s.strip.gsub(/\s+/, " ")
        parts = plan(clean, emotion:, style:)
        cursor = 0
        rendered = parts.map.with_index do |part, index|
          duration = [part[:text].split.length * 355 + part[:pause_ms], 180].max
          row = part.merge(index:, start_ms: cursor, end_ms: cursor + duration, duration_ms: duration)
          cursor += duration
          row
        end
        events = rendered.each_with_index.flat_map do |part, index|
          rows = [{
            at_ms: part[:start_ms],
            type: "phrase",
            index: index,
            role: part[:role],
            energy: phrase_energy(part[:text]),
          }]
          if part[:emphasis] != :none
            rows << {
              at_ms: [part[:start_ms] + 35, part[:end_ms] - 1].min,
              type: "accent",
              index: index,
              emphasis: part[:emphasis],
              rate_delta: part[:rate_delta],
              pitch_delta_hz: part[:pitch_delta_hz],
            }
          end
          rows << {
            at_ms: part[:end_ms],
            type: "pause",
            duration_ms: part[:pause_ms],
            punctuation: punctuation_for(part[:text]),
          }
          if index.positive?
            rows << {
              at_ms: part[:start_ms],
              type: "breath",
              duration_ms: [110, part[:pause_ms]].min,
              energy: [0.7 - score(emotion, :arousal) * 0.25, 0.18].max.round(3),
            }
          end
          rows
        end.sort_by { |event| [event[:at_ms], event[:type]] }
        signature = {
          schema: 1,
          text: clean,
          voice: voice.to_s,
          style: style.to_s,
          rate: rate.to_s,
          pitch: pitch.to_s,
        }
        {
          schema: 1,
          clock: "audio",
          duration_normalization: true,
          performance_id: Digest::SHA256.hexdigest(JSON.generate(signature))[0, 20],
          estimated_duration_ms: [cursor, 1].max,
          voice: voice.to_s,
          style: style.to_s,
          rate: rate.to_s,
          pitch: pitch.to_s,
          phrases: rendered,
          events: events.first(160),
        }
      end

      def punctuation_for(text)
        text.to_s[/([.!?;:—-])\s*$/, 1].to_s
      end

      def apply(base_rate:, base_pitch:, text:, emotion: {}, style: :normal)
        base_rate_value = base_rate.to_s.delete("%").to_i
        base_pitch_value = base_pitch.to_s.delete("Hz").to_i

        plan(text, emotion:, style:).map do |part|
          {
            **part,
            rate: format("%+d%%", (base_rate_value + part[:rate_delta]).clamp(MIN_RATE, MAX_RATE)),
            pitch: format("%+dHz", (base_pitch_value + part[:pitch_delta_hz]).clamp(MIN_PITCH_HZ, MAX_PITCH_HZ)),
          }
        end
      end

      def score(emotion, key)
        emotion.dig(:scores, key).to_f.clamp(0.0, 1.0)
      end

      def smooth_step(value, previous, limit)
        value.clamp(previous - limit, previous + limit)
      end

      def sentence_role(text, index, total)
        return :opening if index.zero? && total > 1
        return :closing if index == total - 1 && total > 1
        return :question if text.end_with?("?")
        return :warning if text.match?(/\b(warn|warning|careful|risk|unsafe|danger|blocked|failed|error|critical)\b/i)
        return :reveal if text.match?(/\b(the key|the point|interestingly|surprisingly|here's why|what matters)\b/i)
        return :contrast if text.match?(/\b(but|however|instead|actually|except|rather|yet|still)\b/i)
        return :parenthetical if text.match?(/[()—–]/)
        return :list_item if text.match?(/\A(?:\d+[.)]|[-*])\s+/)
        return :soft_landing if index == total - 1 && text.split.length <= 8

        :body
      end

      def pause_ms_for(role, index, total, emotion)
        base = {
          opening: 105,
          setup: 150,
          delivery: 210,
          parenthetical: 135,
          contrast: 250,
          reveal: 300,
          question: 185,
          warning: 245,
          list_item: 155,
          soft_landing: 285,
          closing: 380,
          body: DEFAULT_PAUSE_MS,
        }.fetch(role, DEFAULT_PAUSE_MS)
        base += 35 if %i[reveal contrast warning].include?(role)
        base += (index * 10)
        base -= (score(emotion, :arousal) * 55).round
        base += (score(emotion, :intimacy) * 38).round
        base += (score(emotion, :tension) * 25).round if emotion.dig(:scores, :tension)
        return [MIN_PAUSE_MS, MAX_PAUSE_MS].min if total <= 1 && index.zero?

        base.clamp(MIN_PAUSE_MS, MAX_PAUSE_MS)
      end

      def emphasis_for(role, text)
        return :strong if %i[warning reveal].include?(role)
        return :question if role == :question
        return :light if text.split.length <= 7

        :none
      end

      def apply_emphasis(rate, pitch, emphasis)
        case emphasis
        when :strong then [rate - 1, pitch + 4]
        when :question then [rate, pitch + 5]
        when :light then [rate + 1, pitch + 2]
        else [rate, pitch]
        end
      end

      def arc_factor(index, total)
        return 0.0 if total <= 2

        midpoint = (total - 1) / 2.0
        1.0 - ((index - midpoint).abs / midpoint)
      end
    end
  end
end
