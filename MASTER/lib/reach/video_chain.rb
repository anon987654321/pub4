# frozen_string_literal: true

module Master
  module Reach
    module VideoChain
      HELP = <<~TEXT.strip
        ok: video routing
        cloud: /repligen or Replicate API (data/providers.yml)
        local identity LoRA: /lora-train (lora/training/ragnhild/ai_toolkit/)
        grade stills: /postpro (MASTER/tools/postpro.rb)
      TEXT

      module_function

      def help = HELP
    end
  end
end