# frozen_string_literal: true

module Shared
  module MediaGuard
    extend ActiveSupport::Concern

    MEDIA_MAX_BYTES = Integer(ENV.fetch("RAILS_SHARED_MEDIA_MAX_BYTES", 20 * 1024 * 1024))
    MEDIA_ALLOWED_TYPES = %w[image/jpeg image/png image/webp image/heic image/heif].freeze

    private

    def validate_media_upload(upload)
      return :missing unless upload.respond_to?(:read)
      return :too_large if upload.respond_to?(:size) && upload.size.to_i > MEDIA_MAX_BYTES
      return :unsupported unless MEDIA_ALLOWED_TYPES.include?(upload.content_type.to_s.downcase)

      :ok
    end

    def safe_upload_name(name, fallback: "upload")
      base = File.basename(name.to_s)
      ext = File.extname(base).downcase
      stem = File.basename(base, ext).gsub(/[^A-Za-z0-9._-]+/, "_").sub(/\A[._-]+/, "")
      stem = fallback if stem.empty?
      "#{stem}#{ext}"
    end
  end
end
