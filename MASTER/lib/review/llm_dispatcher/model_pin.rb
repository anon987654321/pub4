# frozen_string_literal: true

module Master
  module Review
    class LLMDispatcher
      # One call answered by a named model, past MASTER_MODEL: /fix sends every
      # repair to Opus and asks a cheaper model whether the diff is safe. Per
      # thread, because the repair stream runs several files at once.
      module ModelPin
        KEY = :master_model_pin

        def self.with(model)
          return yield if model.to_s.strip.empty?

          previous = Thread.current[KEY]
          Thread.current[KEY] = model
          begin
            yield
          ensure
            Thread.current[KEY] = previous
          end
        end

        def self.current = Thread.current[KEY]
      end
    end
  end
end
