# frozen_string_literal: true

module Shared
  class MediaProcessingJob < ApplicationJob
    queue_as :bulk

    def perform(record_class_name, record_id, attachment_name, variants: {})
      model = record_class_name.to_s.safe_constantize
      unless model.is_a?(Class) && model < ActiveRecord::Base
        raise ArgumentError, "media record class is not an ActiveRecord model: #{record_class_name}"
      end

      record = model.find(record_id)
      reflection = record.class.respond_to?(:reflect_on_attachment) && record.class.reflect_on_attachment(attachment_name)
      unless reflection
        raise ArgumentError, "media attachment is not declared: #{record.class.name}##{attachment_name}"
      end

      attachment = record.public_send(attachment_name)
      files = attachment.respond_to?(:attachments) ? attachment.attachments : Array(attachment)

      files.each do |file|
        next unless file.respond_to?(:variable?) && file.variable?
        next unless file.content_type.to_s.start_with?("image/")

        variants.each do |name, options|
          file.variant(options.symbolize_keys).processed
          Rails.logger.info("media variant processed #{record_class_name}##{record_id} #{attachment_name}.#{name}")
        end
      end
    end
  end
end
