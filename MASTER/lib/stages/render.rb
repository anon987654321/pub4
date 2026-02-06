# frozen_string_literal: true

module MASTER
  module Stages
    class Render
      def call(input)
        response = input[:response] || input["response"] || ""
        
        formatted = Typography.format(response)
        
        Result.ok(input.merge(rendered: formatted))
      end
    end
  end
end
