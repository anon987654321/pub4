# frozen_string_literal: true

module Master
  class Result
    # Functor/monad composition for Result::Ok (map/flat_map/and_then) — kept
    # separate from Ok's own value-identity methods (ok?/value!/unwrap/...).
    module OkChaining
      def map(&blk) = Result.ok(blk.call(@value))
      def flat_map(&blk) = blk.call(@value)

      def and_then(label = nil, &blk)
        result = blk.call(@value)
        result.is_a?(Result) ? result : Result.ok(result)
      rescue StandardError => e
        Result.err("#{label || "stage"}: #{e.message}", category: :infrastructure)
      end
    end
  end
end
