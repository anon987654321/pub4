# frozen_string_literal: true

module Bridges
  module Repligen
    class Pipelines
      MAX_TRAINING_PHOTOS = 24
      COMMERCIAL_VARIATIONS = 4

      def initialize(actor:, account:, options: {})
        @actor = actor
        @account = account
        @options = options || {}
      end

      def execute_chain
        enforce_replicate!

        pipeline_steps = build_pipeline_steps
        return if pipeline_steps.empty?

        pipeline_steps.each do |step|
          case step[:type]
          when :commercial
            generate_commercial(step)
          when :training_photos
            enhance_training_photos(step)
          else
            raise ArgumentError, "Unknown pipeline step type: #{step[:type]}"
          end
        end
      end

      private

      attr_reader :actor, :account, :options

      def enforce_replicate!
        return if defined?(Replicate)

        raise LoadError, %(Replicate gem is required for Bridges::Repligen::Pipelines)
      end

      def build_pipeline_steps
        chain = self.class.pipeline_chain
        return [] if chain.nil? || chain.empty?

        chain.map do |chain_step|
          normalize_pipeline_step(chain_step)
        end
      end

      def normalize_pipeline_step(chain_step)
        step_hash = chain_step.is_a?(Hash) ? chain_step : { type: chain_step }
        {
          type: step_hash.fetch(:type, nil)&.to_sym,
          model: step_hash.fetch(:model, nil),
          prompt: step_hash.fetch(:prompt, nil),
          training_album_id: step_hash.fetch(:training_album_id, nil),
          commercial_count: step_hash.fetch(:commercial_count, COMMERCIAL_VARIATIONS)
        }
      end

      def generate_commercial(step)
        enforce_replicate!

        commercial_model = step.fetch(:model, nil)
        prompt_text = step.fetch(:prompt, nil)
        count = step.fetch(:commercial_count, COMMERCIAL_VARIATIONS).to_i

        return if commercial_model.nil? || prompt_text.nil?
        return if count <= 0

        count.times do
          Replicate.run(commercial_model, input: { prompt: prompt_text })
        end
      end

      def enhance_training_photos(step)
        enforce_replicate!

        training_album_id = step.fetch(:training_album_id, nil)
        return if training_album_id.nil?

        training_album = training_albums_scope.find_by(id: training_album_id)
        return if training_album.nil?

        photos_to_enhance = training_album.photos.limit(MAX_TRAINING_PHOTOS)
        return if photos_to_enhance.empty?

        photos_to_enhance.each do |photo|
          enhance_photo(photo)
        end
      end

      def training_albums_scope
        account
          .training_albums
          .includes(:photos)
      end

      def enhance_photo(photo)
        model = options.fetch(:training_model, nil)
        prompt = options.fetch(:training_prompt, nil)

        return if model.nil? || prompt.nil?

        Replicate.run(model, input: { image: photo.url, prompt: prompt })
      end

      class << self
        def pipeline_chain
          @pipeline_chain ||= []
        end

        def configure_chain(chain_steps)
          @pipeline_chain = Array(chain_steps)
        end
      end
    end
  end
end