# frozen_string_literal: true

require "digest"

module Master
  module Review
    module Council
      # A tribunal persona's speaking identity. This is deliberately separate
      # from Master::Voice::Policy: normal MASTER speech keeps its single-source
      # policy, while /fix tribunal jurors are a cast of distinct speakers.
      Profile = Data.define(
        :voice,
        :rate,
        :pitch,
        :style,
        :vernacular,
        :speech_pattern,
        :pause_after,
      ) do
        def to_h
          {
            voice:,
            rate:,
            pitch:,
            style:,
            vernacular:,
            speech_pattern:,
            pause_after:,
          }
        end
      end

      module VoiceProfile
        VOICES = {
          "Architect" => "en-US-AndrewNeural",
          "Data Steward" => "en-US-JaneNeural",
          "Ethics & Policy" => "en-US-AriaNeural",
          "Maintainer" => "en-US-BrianNeural",
          "Performance" => "en-US-DavisNeural",
          "Product Strategist" => "en-US-EmmaNeural",
          "QA Engineer" => "en-GB-RyanNeural",
          "Pragmatist" => "en-US-GuyNeural",
          "Reliability" => "en-GB-NoahNeural",
          "Security" => "en-GB-ThomasNeural",
          "Skeptic" => "en-GB-EthanNeural",
          "User Advocate" => "en-CA-LiamNeural",
          "Accessibility" => "en-CA-ClaraNeural",
          "Graphic Designer" => "en-US-BreeNeural",
          "Web Designer" => "en-GB-LibbyNeural",
          "Electronic Music Producer" => "en-US-AvaNeural",
          "Layperson" => "en-NZ-MitchellNeural",
          "Hip-Hop Producer" => "en-US-KaiNeural",
          "Sound Engineer" => "en-US-JasonNeural",
          "Sound Designer" => "en-US-LunaNeural",
          "Label Executive" => "en-GB-OliverNeural",
          "Organ Composer" => "en-IE-ConnorNeural",
          "Google CSS Engineer" => "en-US-SaraNeural",
          "Typographer" => "en-GB-HollieNeural",
          "Cognitive Psychologist" => "en-US-TonyNeural",
          "NNGroup UX Researcher" => "en-US-NancyNeural",
        }.freeze

        module_function

        def profile(voice, rate, pitch, style, vernacular, speech_pattern, pause_after)
          Profile.new(
            voice:,
            rate:,
            pitch:,
            style:,
            vernacular:,
            speech_pattern:,
            pause_after:,
          )
        end
        private_class_method :profile

        PROFILES = {
          "Architect" => profile("en-US-AndrewNeural", "-8%", "-12Hz", :deep, "boundary, interface, coupling", :measured, 1),
          "Data Steward" => profile("en-US-JaneNeural", "-5%", "+2Hz", :clear, "lineage, source row, provenance", :self_correcting, 1),
          "Ethics & Policy" => profile("en-US-AriaNeural", "-2%", "+8Hz", :warm, "in practice, policy, people", :pause_heavy, 2),
          "Maintainer" => profile("en-US-BrianNeural", "-6%", "-8Hz", :calm, "at 3am, maintenance, simpler", :dry, 1),
          "Performance" => profile("en-US-DavisNeural", "+9%", "-4Hz", :brief, "hot path, latency, allocation", :clipped, 1),
          "Product Strategist" => profile("en-US-EmmaNeural", "+1%", "+4Hz", :warm, "value, leverage, user outcome", :questioning, 2),
          "QA Engineer" => profile("en-GB-RyanNeural", "+4%", "+0Hz", :clear, "repro, expected, actual", :staccato, 1),
          "Pragmatist" => profile("en-US-GuyNeural", "+7%", "-2Hz", :brief, "smallest useful change, ship", :compressed, 1),
          "Reliability" => profile("en-GB-NoahNeural", "-10%", "-18Hz", :deep, "failure mode, cascade, rollback", :pause_heavy, 2),
          "Security" => profile("en-GB-ThomasNeural", "+2%", "-10Hz", :dramatic, "attack surface, trust boundary, exploit", :emphatic, 1),
          "Skeptic" => profile("en-GB-EthanNeural", "-3%", "-5Hz", :neutral, "show me the evidence, falsify", :false_start, 2),
          "User Advocate" => profile("en-CA-LiamNeural", "-1%", "+3Hz", :warm, "from the user's side, friction", :colloquial, 1),
          "Accessibility" => profile("en-CA-ClaraNeural", "-4%", "+6Hz", :clear, "keyboard, focus, screen reader", :deliberate, 2),
          "Graphic Designer" => profile("en-US-BreeNeural", "+0%", "+10Hz", :ethereal, "composition, hierarchy, figure-ground", :breathy, 2),
          "Web Designer" => profile("en-GB-LibbyNeural", "+3%", "+2Hz", :clear, "native, browser, semantic", :precise, 1),
          "Electronic Music Producer" => profile("en-US-AvaNeural", "-4%", "+4Hz", :soulful, "groove, pocket, swing", :beat_locked, 1),
          "Layperson" => profile("en-NZ-MitchellNeural", "-2%", "-1Hz", :warm, "plainly, in normal words", :hesitant, 2),
          "Hip-Hop Producer" => profile("en-US-KaiNeural", "+5%", "-8Hz", :deep, "knock, pocket, bounce", :cadenced, 1),
          "Sound Engineer" => profile("en-US-JasonNeural", "+0%", "-6Hz", :neutral, "headroom, meter, clipping", :technical, 1),
          "Sound Designer" => profile("en-US-LunaNeural", "-5%", "+12Hz", :intimate, "texture, transient, air", :reflective, 2),
          "Label Executive" => profile("en-GB-OliverNeural", "+2%", "-1Hz", :clear, "release, listener, catalogue", :formal, 1),
          "Organ Composer" => profile("en-IE-ConnorNeural", "-9%", "-22Hz", :storyteller, "voice-leading, register, cadence", :long_pause, 2),
          "Google CSS Engineer" => profile("en-US-SaraNeural", "+6%", "+0Hz", :clear, "cascade, paint, specificity", :staccato, 1),
          "Typographer" => profile("en-GB-HollieNeural", "-3%", "+5Hz", :calm, "measure, rhythm, reading", :careful, 2),
          "Cognitive Psychologist" => profile("en-US-TonyNeural", "-4%", "-3Hz", :neutral, "working memory, recognition, load", :explaining, 2),
          "NNGroup UX Researcher" => profile("en-US-NancyNeural", "+1%", "+7Hz", :clear, "heuristic, task, evidence", :methodical, 1),
        }.freeze

        def for(persona)
          name = persona.respond_to?(:name) ? persona.name.to_s : persona.to_s
          PROFILES.fetch(name) { fallback(name) }
        end

        def unique_for(personas)
          Array(personas).map { |persona| self.for(persona) }
        end

        def render(text, persona:)
          profile = self.for(persona)
          value = text.to_s.strip
          return value if value.empty?

          spoken = vernacular_prefix(value, profile.vernacular)
          apply_speech_pattern(spoken, profile.speech_pattern)
        end

        def fallback(name)
          digest = Digest::SHA256.hexdigest(name.to_s)
          index = digest.to_i(16) % PROFILES.size
          PROFILES.values.fetch(index)
        end

        def vernacular_prefix(text, vernacular)
          return text if vernacular.to_s.empty?

          "#{vernacular.split(", ").first}: #{text}"
        end

        def apply_speech_pattern(text, pattern)
          case pattern.to_sym
          when :false_start
            words = text.split
            words.empty? ? text : "#{words.first} — no, #{text}"
          when :self_correcting
            text.sub(/\b(is|are|was|were)\b/i) { |match| "#{match} — more precisely," }
          when :pause_heavy
            text.gsub(/,\s+/, ", ... ")
          when :breathy
            text.sub(/([.!?])\s+/, "\\1 ... ")
          when :hesitant
            "Well, #{text}"
          when :staccato
            text.gsub(/;\s*/, ". ")
          when :compressed
            text.gsub(/\b(?:really|quite|very|actually)\b\s*/i, "")
          when :emphatic
            text.sub(/\A/, "Look — ")
          when :colloquial
            text.sub(/\A/, "Right, ")
          when :deliberate
            text.gsub(/,\s+/, ", ... ")
          when :beat_locked
            text.gsub(/;\s*/, " — ")
          when :cadenced
            text.gsub(/,\s+/, " — ")
          when :reflective
            text.sub(/\A/, "Mm. ")
          when :formal
            text.sub(/\A/, "The point is: ")
          when :long_pause
            text.gsub(/([.!?])\s+/, "\\1 ... ")
          when :careful
            text.sub(/\A/, "To be precise, ")
          when :explaining
            text.sub(/\A/, "The load here is ")
          when :technical
            text.sub(/\A/, "Measured reading: ")
          when :precise
            text.sub(/\A/, "Concretely, ")
          when :questioning
            text.sub(/\A/, "The question is: ")
          when :dry
            text.sub(/\A/, "At three in the morning: ")
          when :methodical
            text.sub(/\A/, "Step by step, ")
          else
            text
          end
        end
      end
    end
  end
end
