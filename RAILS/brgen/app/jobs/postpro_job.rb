# frozen_string_literal: true

class PostproJob < ApplicationJob
  queue_as :bulk

  VALID_PRESETS = Shared::PostproProcessor::VALID_PRESETS.freeze

  def perform(record_gid, preset, attachment_name = "image")
    record = GlobalID::Locator.locate(record_gid)
    return unless record
    return unless VALID_PRESETS.include?(preset.to_s)

    attachment = record.public_send(attachment_name)
    return unless attachment.attached?

    Shared::PostproProcessor.apply_to_record!(record, attachment_name, preset: preset.to_s, replace: false)
  end
end
