# frozen_string_literal: true

class GarmentSegmentationService
  def self.call(item)
    new(item).call
  end

  def initialize(item)
    @item = item
  end

  def call
    return { status: "no_photo" } unless @item.photos.attached?

    photo = @item.photos.first
    metadata = (photo.metadata || {}).dup
    metadata["segmentation"] = {
      "status" => "processed",
      "mask_ready" => true,
      "processed_at" => Time.current.iso8601,
      "method" => "amber_v1_stub"
    }
    photo.blob.update!(metadata: metadata)

    @item.update!(
      analysis_status: "segmented",
      dominant_color: @item.dominant_color.presence || sample_color(photo)
    ) if @item.respond_to?(:analysis_status)

    Shared::EventEmitter.call("amber.segmentation.complete", item_id: @item.id) if defined?(Shared::EventEmitter)
    metadata["segmentation"]
  end

  private

  def sample_color(photo)
    "#8a8a8a"
  end
end