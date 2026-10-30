# frozen_string_literal: true

module Shared
  module MediaProcessable
    extend ActiveSupport::Concern

    included do
      class_attribute :media_variant_definitions, default: {}
      after_commit :enqueue_media_variant_processing, on: %i[create update]
    end

    class_methods do
      # Symbol values are stored as strings. A variant URL carries its
      # transformations through the JSON message verifier, which hands
      # `format: :webp` back as "webp"; Active Storage digests the Marshal of
      # the hash, so the variant the job pre-built under :webp is not found and
      # the first view builds it again, on the request.
      def process_media_variants(attachment_name, variants:)
        self.media_variant_definitions = media_variant_definitions.merge(
          attachment_name.to_s => variants.transform_values { |step| MediaProcessable.as_decoded(step) },
        )
      end
    end

    # The transformation as a decoded variant URL gives it back. UTF-8, as
    # JSON parses it: Symbol#to_s is US-ASCII, and Marshal records the encoding.
    def self.as_decoded(transformation)
      transformation.transform_values do |value|
        value.is_a?(Symbol) ? String.new(value.name, encoding: Encoding::UTF_8) : value
      end
    end

    # The variants declared here are plain transformation hashes, not Active
    # Storage named variants, so `photo.variant(:card)` raises. This resolves
    # the name to the transformation the processing job pre-builds.
    def media_variant(attachment_name, name)
      public_send(attachment_name).variant(
        media_variant_definitions.fetch(attachment_name.to_s).fetch(name.to_sym),
      )
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
          variants:,
        )
      rescue StandardError => error
        Rails.logger.error(
          "MediaProcessable #{self.class.name}##{id} #{attachment_name}: " \
          "#{error.class}: #{error.message}",
        )
      end
    end
  end
end
