# frozen_string_literal: true

module MASTER
  module Stages
    # Stage 1: Pass text through, load persona
    class Intake
      def call(input)
        text = input[:text] || ""
        Result.ok(input.merge(text: text))
      end
    end
  end
end
