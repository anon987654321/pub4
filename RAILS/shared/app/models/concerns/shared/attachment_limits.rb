# frozen_string_literal: true

module Shared
  # Every upload is held to a size, and an image slot to image types.
  #
  # Twenty-four attachments across the three apps took any file of any size: a
  # listing photo could be a 2 GB archive or an HTML page, stored on a 1 GB box.
  # A controller concern with the right numbers existed and nothing included
  # it, so the limit now lives where every write path passes — the record's
  # validation — rather than in each controller that might remember to call it.
  #
  # The kind is read from the attachment's name, because the name is the only
  # thing every model already declares. A slot named for audio or video takes
  # that family; `media`, `attachment` and `render` carry mixed files and are
  # held to size alone; every other name is an image slot. SVG is not an image
  # type here: it is markup, and serving it back is script on this origin.
  #
  # Only a new upload is checked. A blob already stored stays valid, so a limit
  # tightened later cannot make an existing record unsaveable.
  module AttachmentLimits
    extend ActiveSupport::Concern

    MB = 1024 * 1024

    IMAGE_TYPES = %w[image/jpeg image/png image/webp image/gif image/heic image/heif image/avif].freeze
    # Both time-based kinds take either family: webm, mp4 and ogg are shared
    # containers, and an audio-only recording from Safari identifies as video/mp4.
    TIME_BASED_TYPES = %w[audio/ video/ application/ogg].freeze

    # Each type is matched as a prefix, so "audio/" admits the family and an
    # empty string admits anything.
    KINDS = {
      image: { max_bytes: Integer(ENV.fetch("RAILS_SHARED_MEDIA_MAX_BYTES", 20 * MB)), types: IMAGE_TYPES },
      audio: { max_bytes: Integer(ENV.fetch("RAILS_SHARED_AUDIO_MAX_BYTES", 100 * MB)), types: TIME_BASED_TYPES },
      video: { max_bytes: Integer(ENV.fetch("RAILS_SHARED_VIDEO_MAX_BYTES", 200 * MB)), types: TIME_BASED_TYPES },
      mixed: { max_bytes: Integer(ENV.fetch("RAILS_SHARED_UPLOAD_MAX_BYTES", 200 * MB)), types: [ "" ] },
    }.freeze

    NAMED_KINDS = {
      "audio" => :audio, "audio_file" => :audio,
      "video" => :video, "video_file" => :video,
      "media" => :mixed, "attachment" => :mixed, "render" => :mixed,
    }.freeze

    included do
      validate :new_attachments_within_limits
    end

    def self.kind_for(name) = NAMED_KINDS.fetch(name.to_s, :image)

    private

    def new_attachments_within_limits
      attachment_changes.each do |name, change|
        limits = KINDS.fetch(AttachmentLimits.kind_for(name))
        Array(change.respond_to?(:blobs) ? change.blobs : change.blob).each do |blob|
          attachment_limit_errors(name, blob, limits)
        end
      end
    end

    def attachment_limit_errors(name, blob, limits)
      if blob.byte_size.to_i > limits[:max_bytes]
        errors.add(name, :file_too_large, count: limits[:max_bytes] / MB)
      end
      type = blob.content_type.to_s.downcase
      allowed = limits[:types].any? { |prefix| type.start_with?(prefix) }
      errors.add(name, :file_type_not_allowed) unless allowed
    end
  end
end
