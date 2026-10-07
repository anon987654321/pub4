# frozen_string_literal: true

module Master
  module Voice
    # Fast, deterministic affect analysis for speech and face expression.
    #
    # Lexical signals remain the stable foundation. Structural signals add the
    # things humans hear even when a sentence contains no explicit emotion word:
    # questions, contrast, short punches, lists, parentheses and reflective length.
    module Emotion
      SIGNALS = {
        triumph: /\b(done|complete|success|great|perfect|nice|ready|finished|works|fixed|sorted|boom|nailed|crushed|win|won|solved|landed)\b/i,
        comfort: /\b(sorry|unfortunately|stuck|blocked|fail|error|broken|couldn'?t|didn'?t work|rough|hard|difficult|pain|problem|issue)\b/i,
        humor: /\b(lol|haha|heh|anyway|plot twist|whoops|oops|wild|chaos|honestly|fair enough|not gonna lie|funny|ridiculous)\b/i,
        wonder: /\b(wow|amazing|incredible|beautiful|magic|transcend|transform|world|research|breakthrough|fascinating|strange|wonder)\b/i,
        intimacy: /\b(you|your|we|us|together|cozy|warm|friend|home|care|gentle|soft|with you|for us|again|still)\b/i,
        urgency: /\b(now|quick|hurry|asap|immediately|watch|listen|important|critical|urgent|danger|careful)\b/i,
        lyric: /\b(sing|song|melody|chorus|verse|rhyme|la la|hum|tune|ballad|poem|poetic|dream|remember)\b/i,
      }.freeze

      POSITIVE = /\b(good|great|beautiful|right|love|glad|happy|useful|clear|clean|elegant|better|best|works|solved)\b/i
      NEGATIVE = /\b(bad|wrong|broken|failed|failure|pain|sad|angry|awful|ugly|worse|worst|risk|danger|blocked)\b/i
      HEDGES = /\b(maybe|perhaps|probably|might|could|seems|seem|i think|i suspect|not sure|roughly)\b/i
      CERTAINTY = /\b(definitely|clearly|certainly|exactly|always|never|must|will|is|are|done|ready|fixed)\b/i
      CONTRAST = /\b(but|however|yet|still|instead|actually|except|rather|although|though|while)\b/i
      INTERPERSONAL = /\b(you|your|we|us|together|with you|for you|for us|again|still|care|trust)\b/i
      LYRICAL_SHORT_WORD_COUNT = 14

      STRUCTURAL = {
        question: ->(t) { [t.count("?"), 2].min / 2.0 },
        exclamation: ->(t) { [t.count("!"), 2].min / 2.0 },
        contrast: ->(t) { [t.scan(CONTRAST).length, 3].min / 3.0 },
        list: ->(t) { [t.scan(/,|\band\b|\bor\b/i).length, 4].min / 4.0 },
        parenthetical: ->(t) { [t.scan(/[()\[\]]|—|–|:/).length, 2].min / 2.0 },
        short_punch: ->(t) { t.split.length.between?(1, 6) ? 1.0 : 0.0 },
        long_reflective: ->(t) { t.split.length >= 28 ? 1.0 : 0.0 },
        ellipsis: ->(t) { t.include?("...") || t.include?("…") ? 1.0 : 0.0 },
      }.freeze

      module_function

      def analyze(text)
        t = text.to_s.strip
        lexical = SIGNALS.transform_values { |re| score(t, re) }
        structural = STRUCTURAL.transform_values { |probe| clamp(probe.call(t)) }

        positive = score(t, POSITIVE)
        negative = score(t, NEGATIVE)
        hedges = score(t, HEDGES)
        certainty_words = score(t, CERTAINTY)
        interpersonal = score(t, INTERPERSONAL)

        scores = lexical.dup
        scores[:arousal] = clamp(
          0.28 +
          lexical[:triumph] * 0.24 +
          lexical[:urgency] * 0.30 +
          lexical[:humor] * 0.12 +
          structural[:exclamation] * 0.14 +
          structural[:question] * 0.06 +
          structural[:short_punch] * 0.05,
        )
        scores[:valence] = clamp(
          0.5 +
          positive * 0.28 +
          lexical[:triumph] * 0.24 +
          lexical[:wonder] * 0.16 +
          lexical[:humor] * 0.10 -
          negative * 0.28 -
          lexical[:comfort] * 0.20,
        )
        scores[:intimacy] = clamp(
          0.20 +
          lexical[:intimacy] * 0.34 +
          interpersonal * 0.22 +
          lexical[:comfort] * 0.18 +
          structural[:parenthetical] * 0.05,
        )
        scores[:expressiveness] = clamp(
          0.32 +
          lexical[:humor] * 0.18 +
          lexical[:wonder] * 0.18 +
          lexical[:triumph] * 0.12 +
          structural[:exclamation] * 0.12 +
          structural[:question] * 0.08 +
          structural[:contrast] * 0.08 +
          structural[:ellipsis] * 0.04,
        )
        scores[:lyrical] = clamp(
          lexical[:lyric] * 0.62 +
          structural[:long_reflective] * 0.16 +
          structural[:ellipsis] * 0.08 +
          (t.split.length <= LYRICAL_SHORT_WORD_COUNT ? 0.06 : 0.0) +
          (t.match?(/[!?]/) ? 0.04 : 0.0),
        )
        scores[:certainty] = clamp(0.45 + certainty_words * 0.40 - hedges * 0.42)
        scores[:tension] = clamp(
          lexical[:urgency] * 0.38 +
          lexical[:comfort] * 0.18 +
          structural[:contrast] * 0.24 +
          structural[:question] * 0.12 +
          hedges * 0.08,
        )

        blend = emotion_blend(lexical)
        primary = primary_emotion(lexical)
        mode = emotion_mode(scores)

        {
          primary:,
          blend:,
          mode:,
          structural:,
          scores:,
          exaggeration: clamp(0.42 + scores[:expressiveness] * 0.38 + scores[:arousal] * 0.10).round(2),
          cfg_weight: clamp(0.50 - scores[:urgency] * 0.12 - scores[:humor] * 0.06 + scores[:certainty] * 0.04).round(2),
          warmth: clamp(0.52 + scores[:intimacy] * 0.28 - scores[:urgency] * 0.10).round(2),
        }
      end

      def score(text, regexp)
        [[text.scan(regexp).length * 0.22, 1.0].min, 0.0].max
      end

      def clamp(value)
        [[value.to_f, 0.0].max, 1.0].min
      end

      PRIMARY_THRESHOLDS = [
        [:comfort, 0.35, :comfort],
        [:triumph, 0.30, :triumph],
        [:humor, 0.20, :humor],
        [:wonder, 0.20, :wonder],
        [:urgency, 0.20, :urgent],
      ].freeze

      def primary_emotion(scores)
        _key, _threshold, label = PRIMARY_THRESHOLDS.find { |key, threshold, _label| scores[key] > threshold }
        label || :warm
      end

      def emotion_blend(scores)
        weights = scores.select { |key, _| PRIMARY_THRESHOLDS.any? { |candidate, _, _| candidate == key } }
        total = weights.values.sum
        return { warm: 1.0 } if total <= 0.0

        weights
          .sort_by { |key, value| [-value, key.to_s] }
          .first(3)
          .to_h
          .transform_values { |value| (value / total).round(3) }
      end

      def emotion_mode(scores)
        return :melodic if scores[:lyrical] >= 0.40 || scores[:long_reflective].to_f >= 0.6
        return :expressive if scores[:expressiveness] >= 0.55
        return :tense if scores[:tension] >= 0.45

        :conversational
      end

      private_class_method :score, :clamp, :primary_emotion, :emotion_blend, :emotion_mode
    end
  end
end
