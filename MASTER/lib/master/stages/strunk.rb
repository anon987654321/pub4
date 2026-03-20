# frozen_string_literal: true

module Master
  module Stages
    class Strunk
      PREAMBLES = [
        /\AI.?d be happy to help[,.]?\s*/i,
        /\AGreat question.?\s*/i,
        /\ACertainly.?\s*/i,
        /\AOf course.?\s*/i,
        /\ASure.?\s*/i,
        /\AI.?m glad you asked[,.]?\s*/i,
        /\AThat.?s? a great question[,.]?\s*/i,
      ].freeze

      SUFFIXES = [
        /\s*I hope this helps.?\s*\z/i,
        /\s*Let me know if you (have|need)[^.]*[.]\s*\z/i,
        /\s*Feel free to ask[^.]*[.]\s*\z/i,
        /\s*Is there anything else[^?]*\?\s*\z/i,
      ].freeze

      HEDGES = [
        [/\bI think that\b/i,               ""],
        [/\bI believe that\b/i,             ""],
        [/\bIn my opinion,?\s*/i,           ""],
        [/\bIt.?s worth noting that\s*/i,   ""],
        [/\bPlease note that\s*/i,          ""],
        [/\bKeep in mind that\s*/i,         ""],
        [/\byou can simply\b/i,             "you can"],
        [/\byou can easily\b/i,             "you can"],
        [/\bsimply use\b/i,                 "use"],
        [/\bjust use\b/i,                   "use"],
        [/\bfeel free to\b/i,               ""],
      ].freeze

      def call(ctx)
        output = ctx[:output]
        return Result.ok(ctx) unless output.is_a?(String)
        return Result.ok(ctx) if output.empty?
        return Result.ok(ctx) if output.include?("```")  # never mangle code blocks

        cleaned = output
        PREAMBLES.each { |p| cleaned = cleaned.sub(p, "")  }
        SUFFIXES.each  { |s| cleaned = cleaned.sub(s, "")  }
        HEDGES.each    { |p, r| cleaned = cleaned.gsub(p, r) }

        Result.ok(ctx.merge(output: cleaned.strip))
      end
    end
  end
end
