# frozen_string_literal: true

module Master
  module Voice
    # Affective routing — emotion-disentangled TTS controls (IndexTTS2, CosyVoice, Chatterbox).
    module Emotion
      SIGNALS = {
        triumph: /\b(done|complete|success|great|perfect|nice|ready|finished|works|fixed|sorted|boom|nailed|crushed)\b/i,
        comfort: /\b(sorry|unfortunately|stuck|blocked|fail|error|broken|couldn'?t|didn'?t work|rough|hard)\b/i,
        humor: /\b(lol|haha|heh|anyway|plot twist|whoops|oops|wild|chaos|honestly|fair enough|not gonna lie)\b/i,
        wonder: /\b(wow|amazing|incredible|beautiful|magic|transcend|transform|world|research|breakthrough)\b/i,
        intimacy: /\b(you|your|we|together|cozy|warm|friend|home|care|gentle|soft)\b/i,
        urgency: /\b(now|quick|hurry|asap|immediately|watch|listen|important|critical)\b/i,
        lyric: /\b(sing|song|melody|chorus|verse|rhyme|la la|hum|tune|ballad)\b/i,
      }.freeze

      module_function

      def analyze(text)
        t = text.to_s.strip
        scores = SIGNALS.transform_values { |re| score(t, re) }
        scores[:arousal] = clamp(0.35 + scores[:triumph] * 0.35 + scores[:urgency] * 0.25 + scores[:humor] * 0.2)
        scores[:valence] = clamp(0.5 + scores[:triumph] * 0.35 - scores[:comfort] * 0.4 + scores[:humor] * 0.15 + scores[:wonder] * 0.2)
        scores[:intimacy] = clamp(0.25 + scores[:intimacy] * 0.45 + scores[:comfort] * 0.25)
        scores[:expressiveness] = clamp(0.4 + scores[:humor] * 0.25 + scores[:wonder] * 0.2 + scores[:triumph] * 0.15)
        scores[:lyrical] = clamp(scores[:lyric] + (t.match?(/[!?]/) ? 0.12 : 0.0) + (t.split.length <= 14 ? 0.08 : 0.0))

        primary =
          if scores[:comfort] > 0.35 then :comfort
          elsif scores[:triumph] > 0.3 then :triumph
          elsif scores[:humor] > 0.2 then :humor
          elsif scores[:wonder] > 0.2 then :wonder
          elsif scores[:urgency] > 0.2 then :urgent
          else :warm
          end

        mode =
          if scores[:lyrical] >= 0.45 then :melodic
          elsif scores[:expressiveness] >= 0.65 then :expressive
          else :conversational
          end

        {
          primary: primary,
          mode: mode,
          scores: scores,
          exaggeration: clamp(0.45 + scores[:expressiveness] * 0.45).round(2),
          cfg_weight: clamp(0.55 - scores[:urgency] * 0.2 - scores[:humor] * 0.1).round(2),
          warmth: clamp(0.55 + scores[:intimacy] * 0.3 - scores[:urgency] * 0.15).round(2)
        }
      end

      def score(text, re)
        [[text.scan(re).length * 0.22, 1.0].min, 0.0].max
      end

      def clamp(v)
        [[v, 0.0].max, 1.0].min
      end
      private_class_method :score, :clamp
    end
  end
end
