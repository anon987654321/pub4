# frozen_string_literal: true

require "base64"
require "json"

class ImagePresenter
  PHOTO_UPLOAD_DIR = ChatController::PHOTO_UPLOAD_DIR

  def self.payload_for(token)
    return nil unless token.to_s.match?(/\A[0-9a-f]{24}\z/)

    meta_path = PHOTO_UPLOAD_DIR.join("#{token}.json")
    return nil unless File.file?(meta_path)

    meta = JSON.parse(File.read(meta_path))
    disk_path = meta["path"].to_s
    return nil unless disk_path.start_with?(PHOTO_UPLOAD_DIR.to_s)
    return nil unless File.file?(disk_path)

    {
      data: Base64.strict_encode64(File.binread(disk_path)),
      mime: meta["mime"].to_s.empty? ? "image/jpeg" : meta["mime"].to_s,
      name: meta["name"].to_s.empty? ? File.basename(disk_path) : meta["name"].to_s,
      path: disk_path
    }
  rescue StandardError => e
    Rails.logger.warn("ImagePresenter.payload_for failed: #{e.class}: #{e.message}")
    nil
  end
end