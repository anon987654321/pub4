# frozen_string_literal: true

require "json"
require "fileutils"

module Master
  module Voice
    # Single-voice policy: whatever data/voice.yml locks; style still varies.
    module WarmErratic
      STATE = File.join(Master::ROOT, ".master", "tts_voice_state.json")

      # Read the policy rather than naming a voice: the weight table, pick_voice
      # and surprise_guest each hardcoded :ryan, so flipping voice.yml left
      # three call sites still handing the synthesizer the old voice. Methods,
      # not constants, so this file does not need Policy loaded before it and
      # so `Policy.reload!` is picked up without a restart.
      def self.locked_voice = Policy.single_voice_key

      def self.voices = [[locked_voice, 100]]
      SHORT_WORD_COUNT = 12
      MEDIUM_WORD_COUNT = 24
      LONG_WORD_COUNT = 40

      STYLES = {
        calm: { rate: "-6%", pitch: "-4Hz" },
        intimate: { rate: "-4%", pitch: "-2Hz" },
        storyteller: { rate: "-5%", pitch: "+1Hz" },
        brief: { rate: "+1%", pitch: "+2Hz" },
        energetic: { rate: "+5%", pitch: "+6Hz" },
        question: { rate: "+1%", pitch: "+6Hz" },
        clear: { rate: "-2%", pitch: "+2Hz" },
        amused: { rate: "+2%", pitch: "+4Hz" },
        deadpan: { rate: "-1%", pitch: "+1Hz" },
        chipper: { rate: "+6%", pitch: "+7Hz" },
      }.freeze

      FAST_STYLES = %i[brief clear question amused energetic].freeze

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
        return FAST_STYLES.sample if words <= SHORT_WORD_COUNT

        if words <= MEDIUM_WORD_COUNT
          return %i[amused deadpan energetic brief].sample if t.match?(HUMOR_RE)
          return FAST_STYLES.sample if t.match?(CASUAL_RE)
          return FAST_STYLES.sample
        end

        return FAST_STYLES.sample if t.match?(HUMOR_RE) || t.match?(/[!]{1,2}/)
        return %i[clear storyteller amused energetic].sample if words > LONG_WORD_COUNT

        FAST_STYLES.sample
      end

      def pick_voice(style, _text)
        [WarmErratic.locked_voice, style]
      end

      def surprise_guest
        [WarmErratic.locked_voice, FAST_STYLES.sample]
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

      def remember_voice(voice)
        FileUtils.mkdir_p(File.dirname(STATE))
        File.write(STATE, JSON.generate(voice:, at: Time.now.to_i))
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "WarmErratic.remember_voice")
        nil
      end

      def jitter_rate(rate)
        base = rate.to_s.delete("%").to_i
        value = (base + rand(-2..2)).clamp(-10, 8)
        format("%+d%%", value)
      end

      def jitter_pitch(pitch)
        base = pitch.to_s.delete("Hz").to_i
        value = (base + rand(-3..3)).clamp(-14, 14)
        format("%+dHz", value)
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
