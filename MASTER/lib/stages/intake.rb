# frozen_string_literal: true

module MASTER
  module Stages
    class Intake
      def call(input)
        text = input[:text] || input["text"]
        return Result.err("No text provided") unless text
        
        output = input.merge(text: text)
        
        # Load persona if specified
        if input[:persona] || input["persona"]
          persona_name = input[:persona] || input["persona"]
          persona_data = DB.get_persona(persona_name)
          
          if persona_data
            output = output.merge(
              persona: persona_data[:instructions],
              persona_name: persona_data[:name]
            )
          end
        end
        
        Result.ok(output)
      end
    end
  end
end
