# frozen_string_literal: true

require "base64"
require "fileutils"
require "json"
require "open3"
require "rbconfig"
require "securerandom"

class ImagePresenter
  PHOTO_UPLOAD_DIR = Rails.root.join("tmp", "chat_uploads")
  PHOTO_MAX_BYTES = Integer(ENV.fetch("MASTER_PHOTO_MAX_BYTES", 12 * 1024 * 1024))
  PHOTO_MIME_EXT = {
    "image/jpeg" => ".jpg",
    "image/png" => ".png",
    "image/webp" => ".webp",
    "image/heic" => ".heic",
    "image/heif" => ".heif",
  }.freeze
  DEFAULT_POSTPRO_PRESET = ENV.fetch("MASTER_POSTPRO_PRESET", "portrait")

  def initialize(logger: Rails.logger)
    @logger = logger
  end

  def store(upload)
    return [:bad_request, { error: "missing photo" }] unless upload.respond_to?(:read)

    ext, mime = sniffed_image(upload)
    return [:unsupported_media_type, { error: "unsupported image type" }] unless ext
    return [:payload_too_large, { error: "photo too large" }] if upload_size(upload) > PHOTO_MAX_BYTES

    FileUtils.mkdir_p(PHOTO_UPLOAD_DIR)
    cleanup_old_photos!
    write_upload(upload, mime, ext)
  rescue StandardError => e
    @logger.warn("photo upload failed: #{e.class}: #{e.message}")
    [500, { error: "photo upload failed" }]
  end

  def payload(token)
    return unless token.to_s.match?(/\A[0-9a-f]{24}\z/)

    meta_path = PHOTO_UPLOAD_DIR.join("#{token}.json")
    return unless File.file?(meta_path)

    meta = JSON.parse(File.read(meta_path))
    disk_path = meta["path"].to_s
    return unless upload_path_allowed?(disk_path)
    return unless File.file?(disk_path)

    {
      data: Base64.strict_encode64(File.binread(disk_path)),
      mime: meta["mime"].to_s.empty? ? "image/jpeg" : meta["mime"].to_s,
      name: meta["name"].to_s.empty? ? File.basename(disk_path) : meta["name"].to_s,
      path: disk_path,
    }
  rescue StandardError => e
    @logger.warn("uploaded_image_payload failed: #{e.class}: #{e.message}")
    nil
  end

  private

  def upload_size(upload)
    upload.respond_to?(:size) ? upload.size.to_i : 0
  end

  # Client Content-Type is not evidence. A .exe labelled image/jpeg used to
  # pass the allowlist and land in postpro/libvips as the Falcon user.
  def sniffed_image(upload)
    head = upload.read(16).to_s
    upload.rewind if upload.respond_to?(:rewind)
    case head
    when /\A\xFF\xD8\xFF/n
      [".jpg", "image/jpeg"]
    when /\A\x89PNG\r\n\x1A\n/n
      [".png", "image/png"]
    when /\ARIFF.{4}WEBP/n
      [".webp", "image/webp"]
    when /\A....ftyp(?:heic|heif|mif1|msf1)/n
      [".heic", "image/heic"]
    end
  end

  def write_upload(upload, mime, ext)
    token = SecureRandom.hex(12)
    safe_name = sanitize_filename(upload.original_filename.to_s, fallback_ext: ext)
    original_path = PHOTO_UPLOAD_DIR.join("#{token}_orig#{ext}")
    processed_path = PHOTO_UPLOAD_DIR.join("#{token}_#{DEFAULT_POSTPRO_PRESET}#{ext}")

    File.binwrite(original_path, upload.read)
    processed = postpro_photo(original_path.to_s, processed_path.to_s)
    final_path = processed && File.file?(processed_path) ? processed_path : original_path
    info = metadata(token, final_path, original_path, safe_name, mime, processed_path)
    File.write(PHOTO_UPLOAD_DIR.join("#{token}.json"), JSON.pretty_generate(info))
    [:ok, { token:, name: safe_name, processed: info["processed"], preset: DEFAULT_POSTPRO_PRESET }]
  end

  def metadata(token, final_path, original_path, safe_name, mime, processed_path)
    {
      "token" => token,
      "path" => final_path.to_s,
      "original_path" => original_path.to_s,
      "name" => safe_name,
      "mime" => mime,
      "processed" => final_path == processed_path,
      "preset" => DEFAULT_POSTPRO_PRESET,
      "created_at" => Time.now.utc.iso8601,
    }
  end

  def cleanup_old_photos!
    cutoff = Time.now - 86_400
    Dir.glob(PHOTO_UPLOAD_DIR.join("*")).each do |path|
      File.delete(path) if File.file?(path) && File.mtime(path) < cutoff
    end
  rescue StandardError => e
    @logger.debug("photo cleanup skipped: #{e.message}")
  end

  def sanitize_filename(name, fallback_ext: ".jpg")
    ext = File.extname(name.to_s).downcase
    ext = fallback_ext unless PHOTO_MIME_EXT.value?(ext)
    stem = File.basename(name.to_s, ext).gsub(/[^A-Za-z0-9._-]+/, "_").sub(/\A[._-]+/, "")
    stem = "photo" if stem.empty?
    "#{stem}#{ext}"
  end

  def upload_path_allowed?(disk_path)
    upload_root = PHOTO_UPLOAD_DIR.realpath
    candidate = Pathname.new(disk_path).realpath
    candidate == upload_root || candidate.to_s.start_with?(upload_root.to_s + File::SEPARATOR)
  rescue Errno::ENOENT, Errno::EINVAL
    false
  end

  def postpro_photo(input_path, output_path)
    script = File.join(Master::REPO_ROOT, "STUDIO", "postpro", "postpro.rb")
    return false unless File.file?(script)

    out, status = Open3.capture2e(
      RbConfig.ruby,
      script,
      "--input", input_path,
      "--output", output_path,
      "--preset", DEFAULT_POSTPRO_PRESET,
      chdir: File.dirname(script)
    )
    @logger.info("postpro photo=#{File.basename(input_path)} status=#{status.exitstatus} out=#{out.lines.last}")
    status.success?
  rescue StandardError => e
    @logger.warn("postpro failed: #{e.class}: #{e.message}")
    false
  end
end
