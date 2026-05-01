# frozen_string_literal: true

module Master
  module Stages
    # Memo — extract memories from :user_message only; assistant output ignored to prevent hallucination loops.
    class Memo
      REMEMBER_RE = /\bremember\s+(?:that\s+)?(.{10,200}?)(?:[.!]|$)/im.freeze
      DECISION_RE = /\bwe(?:'ve|\s+have)?\s+decided\s+(?:to\s+)?(.{10,150}?)(?:[.!]|$)/im.freeze
      PREFER_RE   = /\bI\s+prefer\s+(.{5,100}?)(?:[.!]|$)/im.freeze

      def initialize(memory:, event_bus: nil)
        @memory = memory
        @bus    = event_bus
      end

      def call(ctx)
        text = user_text(ctx)
        scan_for_memories(text) if text && !text.empty?
        Result.ok(ctx)
      rescue StandardError => e
        @bus&.publish("memo:error", message: e.message)
        Result.ok(ctx)
      end

      private

      def user_text(ctx)
        ctx[:user_message].to_s
      end

      def scan_for_memories(text)
        text.scan(REMEMBER_RE).each_with_index do |(fact), i|
          @memory.remember("note_#{Time.now.to_i}_#{i}", fact.strip)
        end
        text.scan(DECISION_RE).each_with_index do |(decision), i|
          @memory.remember("decision_#{Time.now.to_i}_#{i}", decision.strip)
        end
        text.scan(PREFER_RE).each_with_index do |(pref), i|
          key = "pref_#{Time.now.to_i}_#{i}_#{pref.split.first(3).join("_").downcase.gsub(/\W/, "")}"
          @memory.remember(key, pref.strip)
        end
      end
    end
  end
end
