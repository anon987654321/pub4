# frozen_string_literal: true

module Master
  module Voice
    # Cozy, funny, slightly unpredictable voice picker — never uncanny.
    module WarmErratic
      VOICES = [
        [:osman, 42],
        [:ryan, 17],
        [:william, 15],
        [:wayne, 14],
        [:finn, 12]
      ].freeze

      STYLES = {
        calm: { rate: "-5%", pitch: "-18Hz" },
        intimate: { rate: "-4%", pitch: "-22Hz" },
        storyteller: { rate: "-7%", pitch: "-12Hz" },
        brief: { rate: "+9%", pitch: "+4Hz" },
        energetic: { rate: "+11%", pitch: "+18Hz" },
        question: { rate: "+3%", pitch: "+14Hz" },
        clear: { rate: "+5%", pitch: "+2Hz" },
        amused: { rate: "+7%", pitch: "+12Hz" },
        deadpan: { rate: "-2%", pitch: "-8Hz" },
        chipper: { rate: "+13%", pitch: "+22Hz" }
      }.freeze

      HUMOR_RE = /\b(lol|haha|heh|anyway|plot twist|whoops|oops|wild|chaos|absolutely|literally|honestly|fair enough|not gonna lie|for what it'?s worth)\b/i
      GOOD_NEWS_RE = /\b(done|complete|success|great|perfect|nice|queued|ready|finished|works|fixed|all set|sorted|boom)\b/i
      BAD_NEWS_RE = /\b(error|fail|broken|blocked|sorry|unfortunately|stuck|couldn'?t|didn'?t work|nope)\b/i
      CASUAL_RE = /\b(sure|yep|yeah|okay|cool|right|got it|no worries)\b/i

      module_function

      def pick(text)
        style = pick_style(text)
        voice, style = pick_voice(style, text)
        cfg = STYLES.fetch(style, STYLES[:calm])
        {
          voice: voice,
          style: style,
          rate: jitter_rate(cfg[:rate]),
          pitch: jitter_pitch(cfg[:pitch])
        }
      end

      def pick_style(text)
        t = text.to_s.strip
        return :calm if t.empty?

        words = t.split.length
        return %i[calm intimate storyteller deadpan].sample if t.match?(BAD_NEWS_RE)
        return %i[chipper energetic brief amused].sample if t.match?(GOOD_NEWS_RE)
        return %i[question clear amused question brief].sample if t.end_with?("?")
        return %i[brief energetic chipper amused question].sample if words <= 8

        if words <= 18
          return %i[amused deadpan brief energetic].sample if t.match?(HUMOR_RE)
          return %i[clear brief amused calm].sample if t.match?(CASUAL_RE)
          return %i[clear brief intimate energetic amused].sample
        end

        return %i[amused energetic brief deadpan chipper].sample if t.match?(HUMOR_RE) || t.match?(/[!]{1,2}/)
        return %i[storyteller calm clear intimate].sample if t.match?(/^\s*[-*•]/m) || words > 45

        %i[calm intimate storyteller storyteller clear amused intimate].sample
      end

      def pick_voice(style, text)
        return [:osman, style] if text.split.length > 35 && rand < 0.62
        return [:ryan, style] if style == :deadpan && rand < 0.7
        return [%i[william osman].sample, style] if style == :chipper && rand < 0.55

        if rand < 0.10
          guest_voice, guest_style = surprise_guest
          return [guest_voice, guest_style]
        end

        [weighted_choice(VOICES), style]
      end

      def surprise_guest
        [
          [:finn, :storyteller],
          [:ryan, :deadpan],
          [:william, :chipper],
          [:wayne, :amused]
        ].sample
      end

      def weighted_choice(items)
        total = items.sum { |_, w| w }
        r = rand * total
        items.each do |name, w|
          r -= w
          return name if r <= 0
        end
        items[0][0]
      end

      def jitter_rate(rate)
        sign = rate.start_with?("+") ? 1 : -1
        val = rate.delete("%+").to_i
        val = [0, val.abs + rand(-2..3)].max
        format("%+d%%", sign * val)
      end

      def jitter_pitch(pitch)
        sign = pitch.start_with?("+") ? 1 : -1
        val = pitch.delete("Hz+").to_i
        val = [0, val.abs + rand(-5..6)].max
        format("%+dHz", sign * val)
      end
      private_class_method :pick_style, :pick_voice, :surprise_guest, :weighted_choice, :jitter_rate, :jitter_pitch
    end
  end
end