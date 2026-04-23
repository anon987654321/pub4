# frozen_string_literal: true

module Master
  module Stages
    # Memo — extract and persist memory from the USER's input only.
    #
    # Previously this scanned the assistant's output for "remember that X",
    # which caused LLM meta-restatements ("I'll remember that you prefer dark
    # themes") to be stored as facts the user never asserted — a classic
    # self-reinforcing hallucination loop.
    #
    # Now only :user_message is scanned. Assistant output is ignored on purpose.
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

      # Only trust the user's words. Assistant output is a potential
      # hallucination source and must never seed memory without explicit
      # user confirmation via the /memory remember command.
      def user_text(ctx)
        ctx[:user_message].to_s
      end

      def scan_for_memories(text)
        text.scan(REMEMBER_RE).each_with_index do |(fact), i|
          @memory.remember("note_#{Time.now.to_i}_#{i}", fact.strip)
        end
        text.scan(DECISION_RE).each do |(decision)|
          @memory.remember("decision_latest", decision.strip)
        end
        text.scan(PREFER_RE).each do |(pref)|
          key = "pref_#{pref.split.first(3).join("_").downcase.gsub(/\W/, "")}"
          @memory.remember(key, pref.strip)
        end
      end
    end
  end
end
