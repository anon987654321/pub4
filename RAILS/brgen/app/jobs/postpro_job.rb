# frozen_string_literal: true

class PostproJob < ApplicationJob
  queue_as :bulk

  VALID_PRESETS = Shared::PostproProcessor::VALID_PRESETS.freeze

  def perform(record_gid, preset, attachment_name = "image")
    record = GlobalID::Locator.locate(record_gid)
    return unless record
    return unless VALID_PRESETS.include?(preset.to_s)

    attachment = record.public_send(attachment_name)
    return mark_photo_status(record, "skipped") unless attachment.attached?
    return mark_photo_status(record, "skipped") if Shared::PostproProcessor.skip?

    ok = Shared::PostproProcessor.apply_to_record!(record, attachment_name, preset: preset.to_s, replace: false)
    mark_photo_status(record, ok ? "done" : "failed")
  end

  private

  # Only Marketplace::Listing carries photo_status today; posts_controller
  # also enqueues this job for a post's single image, which has no such
  # column, so this is a no-op there.
  def mark_photo_status(record, status)
    return unless record.respond_to?(:mark_photo_status!)

    record.mark_photo_status!(status)
  end
end
