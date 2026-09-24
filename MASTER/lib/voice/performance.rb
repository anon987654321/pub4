# frozen_string_literal: true

require "digest"

module Master
  module Voice
    # Engine-agnostic spoken performance plan.
    #
    # Natural speech is not one rate and one pitch for a paragraph. This layer
    # turns the semantic/emotional state into small, bounded phrase changes so
    # every TTS backend can receive the same intent. It deliberately stays
    # conservative: continuity beats theatrical randomness.
    module Performance
      MAX_RATE_DELTA = 5
      MAX_PITCH_DELTA_HZ = 12
      MIN_RATE = -20
      MAX_RATE = 20
      MIN_PITCH_HZ = -60
      MAX_PITCH_HZ = 60
      MIN_PAUSE_MS = 70
      MAX_PAUSE_MS = 420
      DEFAULT_PAUSE_MS = 130

      module_function

      def plan(text, emotion: {}, style: :normal)
        phrases = text.to_s.split(/(?<=[.!?])\s+/).map(&:strip).reject(&:empty?)
        phrases = [text.to_s.strip] if phrases.empty?

        phrases.each_with_index.map do |phrase, index|
          role = sentence_role(phrase, index, phrases.length)
          seed = Digest::SHA256.hexdigest(phrase)[0, 4].to_i(16)
          variation = ((seed % 11) - 5)
          arousal = emotion.dig(:scores, :arousal).to_f.clamp(0.0, 1.0)
          delta = ((variation * (0.55 + arousal * 0.35)).round).clamp(-MAX_RATE_DELTA, MAX_RATE_DELTA)
          pitch = ((variation * 2.0) + role_pitch(role)).round.clamp(-MAX_PITCH_DELTA_HZ, MAX_PITCH_DELTA_HZ)

          {
            text: phrase,
            role: role,
            rate_delta: delta,
            pitch_delta_hz: pitch,
            pause_ms: pause_ms_for(role, index, phrases.length, arousal),
            emphasis: emphasis_for(role, phrase),
            style: style.to_sym,
          }
        end
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

      def sentence_role(text, index, total)
        return :opening if index.zero? && total > 1
        return :closing if index == total - 1 && total > 1
        return :question if text.end_with?("?")
        return :warning if text.match?(/\b(warn|warning|careful|risk|unsafe|danger|blocked|failed|error)\b/i)
        return :contrast if text.match?(/\b(but|however|instead|actually|except|rather)\b/i)
        return :reveal if text.match?(/\b(the key|the point|interestingly|surprisingly|here's why)\b/i)

        :body
      end

      def role_pitch(role)
        { opening: 2, closing: -2, question: 5, warning: -5, contrast: 3, reveal: 4, body: 0 }.fetch(role)
      end

      def pause_ms_for(role, index, total, arousal)
        base = case role
               when :opening then 90
               when :question then 150
               when :warning then 190
               when :contrast, :reveal then 220
               when :closing then 260
               else DEFAULT_PAUSE_MS
               end
        base += 35 if index.positive?
        base -= (arousal * 45).round
        base.clamp(MIN_PAUSE_MS, MAX_PAUSE_MS)
      end

      def emphasis_for(role, text)
        return :strong if %i[warning reveal].include?(role)
        return :question if role == :question
        return :light if text.split.length <= 7

        :none
      end
    end
  end
end
