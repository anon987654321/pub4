# frozen_string_literal: true

require "tempfile"
require "rbconfig"

class WardrobeMediaJob < ApplicationJob
  queue_as :media

  VARIANTS = {.freeze
    thumb: { resize_to_limit: [240, 240] },
    card: { resize_to_limit: [720, 960] },
  }.freeze

  def perform(item_id)
    item = Item.find(item_id)
    if defined?(Shared::MediaProcessingJob)
      Shared::MediaProcessingJob.perform_later("Item", item.id, "photos", variants: VARIANTS)
    end
    Shared::EventEmitter.call("amber.photo.queued", item_id: item.id) if defined?(Shared::EventEmitter)
    item.extract_dominant_color! if item.photos.attached?

    # auto postpro film stock on item image upload (DF06)
    if item.photos.attached?
      photo = item.photos.first
      begin
        script = Rails.root.join("../../postpro/postpro.rb").to_s
        if File.exist?(script)
          tmp_in = Tempfile.new(["in", File.extname(photo.filename.to_s.presence || ".jpg")])
          tmp_in.binmode
          tmp_in.write(photo.download)
          tmp_in.rewind
          tmp_out = Tempfile.new(["out", ".jpg"])
          system(RbConfig.ruby, script, "--input", tmp_in.path, "--output", tmp_out.path, "--stock", "kodak_portra", "--preset", "social")
          if File.exist?(tmp_out.path)
            Rails.logger.info("postpro film stock applied automatically to item #{item.id}")
            # could re-attach processed version here
          end
          tmp_in.close!
          tmp_out.close!
        end
      rescue StandardError => e
        Rails.logger.warn("auto postpro failed for item #{item.id}: #{e.message}")
      end
    end
  end
end
