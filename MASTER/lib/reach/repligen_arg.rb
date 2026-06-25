# frozen_string_literal: true

module Master
  module Reach
    # Strunk-refined prompt expansion for /repligen generate and LLM repligen calls.
    module RepligenArg
      DEFAULT_VIDEO_MODEL = "minimax/video-01-live"
      VIDEO_MODEL_RE = /video|veo|kling|luma|ray|seedance|wan-/i.freeze
      IMAGE_MODEL_RE = /flux|sdxl|stable.?diffusion|imagen|dalle/i.freeze

      module_function

      def refine_generate(arg, agent:, ctx: nil)
        text = arg.to_s.strip
        return text unless text.start_with?("generate ")
        return text unless agent

        rest = text.delete_prefix("generate ").strip
        model, prompt = rest.split(/\s+/, 2)
        return text if prompt.nil? || prompt.strip.empty?
        return text unless refinable_model?(model)

        image = ctx_image(ctx)
        medium = video_model?(model) ? :video : :photo
        refined = GenerationPromptRefiner.refine(prompt: prompt.strip, medium: medium, agent: agent, image: image)
        "generate #{model} #{refined}"
      end

      def refinable_model?(model) = video_model?(model) || image_model?(model)
      def video_model?(model) = model.to_s.match?(VIDEO_MODEL_RE)
      def image_model?(model) = model.to_s.match?(IMAGE_MODEL_RE)

      def ctx_image(ctx)
        ctx[:image] if ctx.respond_to?(:[]) && ctx.key?(:image)
      end
    end
  end
end