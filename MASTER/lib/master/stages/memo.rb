# frozen_string_literal: true

module Master
  module Stages
    # Memo — extract and persist memory from assistant responses.
    #
    # Fires after Strunk, before Render. Scans output for explicit memory
    # requests, decisions, and preferences. Writes to persistent Memory store.
    # Non-fatal: errors pass through without breaking the pipeline.
    class Memo
      REMEMBER_RE = /\bremember\s+(?:that\s+)?(.{10,200}?)(?:[.!]|$)/im.freeze
      DECISION_RE = /\bwe(?:'ve|\s+have)?\s+decided\s+(?:to\s+)?(.{10,150}?)(?:[.!]|$)/im.freeze
      PREFER_RE   = /\bI\s+prefer\s+(.{5,100}?)(?:[.!]|$)/im.freeze

      def initialize(memory:)
        @memory = memory
      end

      def call(ctx)
        text = extract_text(ctx)
        extract_memories(text) if text && !text.empty?
        Result.ok(ctx)
      rescue => e
        $stderr.puts "memo: #{e.message}"
        Result.ok(ctx)
      end

      private

      def extract_text(ctx)
        out = ctx[:output]
        case out
        when Result::Ok  then out.value!.to_s
        when Result::Err then nil
        else                  out.to_s
        end
      end

      def extract_memories(text)
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
