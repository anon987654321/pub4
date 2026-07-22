# frozen_string_literal: true

require "json"
require "fileutils"

module Master
  module Voice
    # Single-voice policy: Ryan (en-GB) only; style still varies.
    module WarmErratic
      STATE = File.join(Master::ROOT, ".master", "tts_voice_state.json")

      VOICES = [
        [:ryan, 100],
      ].freeze

      STYLES = {
        calm: { rate: "-3%", pitch: "-10Hz" },
        intimate: { rate: "+2%", pitch: "-6Hz" },
        storyteller: { rate: "+4%", pitch: "+2Hz" },
        brief: { rate: "+14%", pitch: "+10Hz" },
        energetic: { rate: "+18%", pitch: "+24Hz" },
        question: { rate: "+10%", pitch: "+18Hz" },
        clear: { rate: "+12%", pitch: "+8Hz" },
        amused: { rate: "+15%", pitch: "+16Hz" },
        deadpan: { rate: "+6%", pitch: "+4Hz" },
        chipper: { rate: "+20%", pitch: "+28Hz" },
      }.freeze

      FAST_STYLES = %i[chipper energetic brief amused clear question].freeze

      HUMOR_RE = /\b(lol|haha|heh|anyway|plot twist|whoops|oops|wild|chaos|honestly|fair enough|not gonna lie|for what it'?s worth)\b/i
      GOOD_NEWS_RE = /\b(done|complete|success|great|perfect|nice|queued|ready|finished|works|fixed|all set|sorted|boom)\b/i
      BAD_NEWS_RE = /\b(error|fail|broken|blocked|sorry|unfortunately|stuck|couldn'?t|didn'?t work|nope)\b/i
      CASUAL_RE = /\b(sure|yep|yeah|okay|cool|right|got it|no worries)\b/i

      module_function

      def pick(text)
        style = pick_style(text)
        voice, style = pick_voice(style, text)
        prosody_for(voice, style).tap { |r| remember_voice(r[:voice]) }
      end

      def pick_for_voice(voice, text, style: nil)
        resolved_style = style || pick_style(text)
        prosody_for(voice, resolved_style)
      end

      def bad_news?(text)
        return false if text.match?(/\b(fixed|fix|works|working|faster|improved|updated|live|ready)\b/i)

        text.match?(BAD_NEWS_RE)
      end

      def pick_style(text)
        t = text.to_s.strip
        return :calm if t.empty?

        words = t.split.length
        return %i[calm intimate].sample if bad_news?(t)
        return %i[chipper energetic amused brief].sample if t.match?(GOOD_NEWS_RE)
        return FAST_STYLES.sample if t.end_with?("?")
        return FAST_STYLES.sample if words <= 12

        if words <= 24
          return %i[amused deadpan energetic brief].sample if t.match?(HUMOR_RE)
          return FAST_STYLES.sample if t.match?(CASUAL_RE)
          return FAST_STYLES.sample
        end

        return FAST_STYLES.sample if t.match?(HUMOR_RE) || t.match?(/[!]{1,2}/)
        return %i[clear storyteller amused energetic].sample if words > 40

        FAST_STYLES.sample
      end

      def pick_voice(style, _text)
        [:ryan, style]
      end

      def surprise_guest
        [:ryan, FAST_STYLES.sample]
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

      def last_voice
        return unless File.file?(STATE)

        JSON.parse(File.read(STATE)).fetch("voice", nil)&.to_sym
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "WarmErratic.last_voice")
        nil
      end

      def remember_voice(voice)
        FileUtils.mkdir_p(File.dirname(STATE))
        File.write(STATE, JSON.generate(voice:, at: Time.now.to_i))
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "WarmErratic.remember_voice")
        nil
      end

      def jitter_rate(rate)
        sign = rate.start_with?("+") ? 1 : -1
        val = rate.delete("%+").to_i
        val = [0, val.abs + rand(0..4)].max
        boosted = sign * val
        boosted = [boosted, 6].max unless sign.negative?
        format("%+d%%", boosted)
      end

      def jitter_pitch(pitch)
        sign = pitch.start_with?("+") ? 1 : -1
        val = pitch.delete("Hz+").to_i
        val = [0, val.abs + rand(-2..8)].max
        format("%+dHz", sign * val)
      end

      def prosody_for(voice, style)
        cfg = STYLES.fetch(style, STYLES[:clear])
        {
          voice: voice.to_sym,
          style:,
          rate: jitter_rate(cfg[:rate]),
          pitch: jitter_pitch(cfg[:pitch]),
        }
      end
      private_class_method :bad_news?, :pick_style, :pick_voice, :surprise_guest, :weighted_choice, :jitter_rate, :jitter_pitch, :prosody_for
    end
  end
end
