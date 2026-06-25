# frozen_string_literal: true

class GenerateComicStripJob < ApplicationJob
  queue_as :default

  def perform(comic_strip_id)
    comic_strip = ComicStrip.find(comic_strip_id)
    result = ReplicateService.new.generate_comic_strip(
      prompt: comic_strip.prompt,
      style: comic_strip.style
    )

    if result["id"]
      comic_strip.update!(status: "processing", prediction_id: result["id"])
    else
      comic_strip.update!(status: "failed")
      Rails.logger.error "GenerateComicStripJob failed: #{result["error"]}"
    end
  rescue StandardError => e
    comic_strip&.update!(status: "failed")
    Rails.logger.error "GenerateComicStripJob error: #{e.message}"
  end
end