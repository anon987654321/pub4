# frozen_string_literal: true

module Master
  module CLI
    module Stages
      # Memory — one stage for durable user/project memories and voice episodes.
      class Memory
        REMEMBER_RE = /\bremember\s+(?:that\s+)?(.{10,200}?)(?:[.!]|$)/im.freeze
        DECISION_RE = /\bwe(?:'ve|\s+have)?\s+decided\s+(?:to\s+)?(.{10,150}?)(?:[.!]|$)/im.freeze
        PREFER_RE = /\bI\s+prefer\s+(.{5,100}?)(?:[.!]|$)/im.freeze
        ROLE_RE = /\bI(?:'m| am)\s+(?:a\s+|the\s+)?([a-z][a-z\s-]{3,40}?)(?:[.,!]|\s+(?:and|but|so|who))/im.freeze
        DONT_RE = /\b(?:don'?t|stop|never)\s+(.{5,120}?)(?:[.!]|$)/im.freeze
        EPISODE_CHARS = 160

        def initialize(memory:, event_bus: nil)
          @memory = memory
          @bus = event_bus
        end

        def call(ctx)
          return Result.ok(ctx) unless @memory
          text = ctx.user_message.to_s.strip
          remember_user_text(text) unless text.empty?
          record_episode(ctx, text) if ctx.voice && !text.empty?
          Result.ok(ctx)
        rescue StandardError => e
          @bus&.publish("memory:error", message: e.message)
          Result.ok(ctx)
        end

        private

        def record_episode(ctx, user_text)
          reply = ctx.rendered.to_s
          digest = "user: #{user_text[0, EPISODE_CHARS]} | reply: #{reply[0, EPISODE_CHARS]}"
          @memory.remember("episode_#{Time.now.to_i}", digest, type: "general")
        end

        def remember_user_text(text)
          ts = Time.now.to_i
          remember_matches(text:, regexp: REMEMBER_RE, prefix: "note", type: "general", timestamp: ts)
          remember_matches(text:, regexp: DECISION_RE, prefix: "decision", type: "project", timestamp: ts)
          remember_matches(text:, regexp: DONT_RE, prefix: "rule", type: "feedback", timestamp: ts) { |value| "don't #{value}" }
          remember_preferences(text, ts)
          remember_role(text)
        end

        def remember_matches(text:, regexp:, prefix:, type:, timestamp:)
          text.scan(regexp).each_with_index do |(value), i|
            value = yield(value.strip) if block_given?
            @memory.remember("#{prefix}_#{timestamp}_#{i}", value.strip, type:)
          end
        end

        def remember_preferences(text, ts)
          text.scan(PREFER_RE).each_with_index do |(pref), i|
            key = "pref_#{ts}_#{i}_#{pref.split.first(3).join("_").downcase.gsub(/\W/, "")}"
            @memory.remember(key, pref.strip, type: "feedback")
          end
        end

        def remember_role(text)
          match = text.match(ROLE_RE)
          return unless match

          role = match[1].strip
          filler = /\b(?:going|trying|sure|thinking|writing)\b/i
          @memory.remember("user_role", role, type: "user") unless role.length < 4 || role.match?(filler)
        end
      end
    end
  end
end
