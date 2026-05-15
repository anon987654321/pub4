# frozen_string_literal: true

module Master
  module Now
  module Stages
    # Memo — extract memories from :user_message only; assistant output ignored to prevent hallucination loops.
    class Memo
      REMEMBER_RE   = /\bremember\s+(?:that\s+)?(.{10,200}?)(?:[.!]|$)/im.freeze
      DECISION_RE   = /\bwe(?:'ve|\s+have)?\s+decided\s+(?:to\s+)?(.{10,150}?)(?:[.!]|$)/im.freeze
      PREFER_RE     = /\bI\s+prefer\s+(.{5,100}?)(?:[.!]|$)/im.freeze
      ROLE_RE       = /\bI(?:'m| am)\s+(?:a\s+|the\s+)?([a-z][a-z\s-]{3,40}?)(?:[.,!]|\s+(?:and|but|so|who))/im.freeze
      DONT_RE       = /\b(?:don'?t|stop|never)\s+(.{5,120}?)(?:[.!]|$)/im.freeze
      EPISODE_CHARS = 160

      def initialize(memory:, event_bus: nil)
        @memory = memory
        @bus    = event_bus
      end

      def call(ctx)
        text = user_text(ctx)
        scan_for_memories(text) if text && !text.empty?
        record_episode(ctx, text) if ctx[:voice] && text && !text.empty?
        Result.ok(ctx)
      rescue StandardError => e
        @bus&.publish("memo:error", message: e.message)
        Result.ok(ctx)
      end

      private

      def user_text(ctx)
        ctx[:user_message].to_s
      end

      def record_episode(ctx, user_text)
        reply  = ctx[:rendered].to_s
        digest = "user: #{user_text[0, EPISODE_CHARS]} | reply: #{reply[0, EPISODE_CHARS]}"
        @memory.remember("episode_#{Time.now.to_i}", digest, type: "general")
      end

      def scan_for_memories(text)
        ts = Time.now.to_i
        text.scan(REMEMBER_RE).each_with_index do |(fact), i|
          @memory.remember("note_#{ts}_#{i}", fact.strip, type: "general")
        end
        text.scan(DECISION_RE).each_with_index do |(decision), i|
          @memory.remember("decision_#{ts}_#{i}", decision.strip, type: "project")
        end
        text.scan(PREFER_RE).each_with_index do |(pref), i|
          key = "pref_#{ts}_#{i}_#{pref.split.first(3).join("_").downcase.gsub(/\W/, "")}"
          @memory.remember(key, pref.strip, type: "feedback")
        end
        text.scan(DONT_RE).each_with_index do |(rule), i|
          @memory.remember("rule_#{ts}_#{i}", "don't #{rule.strip}", type: "feedback")
        end
        if (m = text.match(ROLE_RE))
          role = m[1].strip
          filler = /\b(?:going|trying|sure|thinking|writing)\b/i
          @memory.remember("user_role", role, type: "user") unless role.length < 4 || role =~ filler
        end
      end
    end
  end
  end
end
