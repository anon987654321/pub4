# frozen_string_literal: true

module Shared
  module MediaProcessable
    extend ActiveSupport::Concern

    included do
      class_attribute :media_variant_definitions, default: {}
      after_commit :enqueue_media_variant_processing, on: %i[create update]
    end

    class_methods do
      def process_media_variants(attachment_name, variants:)
        self.media_variant_definitions = media_variant_definitions.merge(
          attachment_name.to_s => variants
        )
      end
    end

    private

    def enqueue_media_variant_processing
      media_variant_definitions.each do |attachment_name, variants|
        attachment = public_send(attachment_name)
        next unless attachment.respond_to?(:attached?) && attachment.attached?

        # Called on the instance, not perform_later / perform_now: nothing on
        # vm23 runs the queue, and perform_now still inherits ApplicationJob's
        # three polynomial retries — a vips failure would hold the upload ~20s.
        Shared::MediaProcessingJob.new.perform(
          self.class.name,
          id,
          attachment_name,
          variants: variants
        )
      rescue StandardError => error
        Rails.logger.error(
          "MediaProcessable #{self.class.name}##{id} #{attachment_name}: " \
          "#{error.class}: #{error.message}"
        )
      end
    end
  end
end
