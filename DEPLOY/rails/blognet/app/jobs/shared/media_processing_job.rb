# frozen_string_literal: true

module Shared
  class MediaProcessingJob < ApplicationJob
    queue_as :media

    def perform(record_class_name, record_id, attachment_name, variants: {})
      record = record_class_name.constantize.find(record_id)
      attachment = record.public_send(attachment_name)
      files = attachment.respond_to?(:attachments) ? attachment.attachments : Array(attachment)

      files.each do |file|
        next unless file.respond_to?(:variable?) && file.variable?

        variants.each do |name, options|
          file.variant(options.symbolize_keys).processed
          Rails.logger.info("media variant processed #{record_class_name}##{record_id} #{attachment_name}.#{name}")
        end
      end
    end
  end
end
