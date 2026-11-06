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
        # A save that never touched the attachment - a title edit, a
        # visibility flag - re-ran vips over every declared variant inline in
        # the request, on every update of every including model. Only bytes
        # that changed earn processing: the attached attribute participates
        # in dirty tracking, so saved_change_to_<name>? is the cheap answer
        # (the same question post.rb asks of title/content). A model where
        # the method is somehow absent keeps the old always-process shape.
        next if attachment_changed_for_processing?(attachment_name) == false

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

    # nil when the answer is unavailable (no dirty-tracking method): the
    # caller then processes, as before. false only when the save provably
    # did not touch this attachment. Deliberately not named
    # attachment_changed? - models with a has_one_attached :attachment get
    # that method generated, and overriding it would change its meaning.
    def attachment_changed_for_processing?(attachment_name)
      method = "saved_change_to_#{attachment_name}?"
      return unless respond_to?(method, true)

      public_send(method)
    end
  end
end
