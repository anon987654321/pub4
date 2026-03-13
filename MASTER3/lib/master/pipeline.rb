# frozen_string_literal: true

module Master
  class Pipeline
    def initialize(stages)
      @stages = stages
    end

    def call(initial)
      @stages.reduce(initial) { |result, stage|
        result.and_then(stage.class.name) { |ctx| stage.call(ctx) }
      }
    end
  end
end
