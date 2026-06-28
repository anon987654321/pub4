# frozen_string_literal: true

require "fileutils"
require "open3"

module Master
  module Reach
    # Caption-named image zips for ostris/flux-dev-lora-trainer (mirrors DEPLOY/repligen Zipper).
    module CharacterLoraZip
      IMAGE_GLOB = "*.{jpg,jpeg,JPG,JPEG,png,PNG,webp,WEBP}".freeze
      RECOMMENDED_MIN = 12
      RECOMMENDED_MAX = 18

      class Error < StandardError; end

      module_function

      def collect_images(photos_dir)
        Dir.glob(File.join(photos_dir, IMAGE_GLOB))
          .select { |path| File.file?(path) }
          .uniq { |path| File.expand_path(path) }
          .sort
      end

      def captioned_copies(images, trigger_word, staging_dir)
        FileUtils.mkdir_p(staging_dir)
        images.each_with_index.map do |src, index|
          ext = File.extname(src).downcase
          ext = ".jpg" if ext.empty?
          caption = format("a_photo_of_%s_%02d%s", trigger_word, index + 1, ext)
          dest = File.join(staging_dir, caption)
          FileUtils.cp(src, dest)
          dest
        end
      end

      def validate(photos_dir, trigger_word: "subjectxyz")
        images = collect_images(photos_dir)
        issues = []
        warnings = []

        issues << "no images in #{photos_dir}" if images.empty?
        if images.size.positive? && images.size < RECOMMENDED_MIN
          warnings << "only #{images.size} images (Replicate recommends #{RECOMMENDED_MIN}-#{RECOMMENDED_MAX} for character LoRAs)"
        end
        warnings << "#{images.size} images exceeds typical #{RECOMMENDED_MAX}-image sweet spot" if images.size > RECOMMENDED_MAX

        images.each do |path|
          size = File.size(path)
          warnings << "#{File.basename(path)} is only #{size} bytes — may be too small" if size < 20_000
        end

        { images: images, issues: issues, warnings: warnings, trigger_word: trigger_word }
      end

      def zip(photos_dir, out_path, trigger_word: "subjectxyz")
        images = collect_images(photos_dir)
        raise Error, "no images in #{photos_dir}" if images.empty?

        staging_dir = File.join(File.dirname(out_path), "lora_staging_#{Process.pid}")
        FileUtils.rm_rf(staging_dir)
        captioned = captioned_copies(images, trigger_word, staging_dir)

        File.delete(out_path) if File.exist?(out_path)
        run_zip(%W[-jq #{out_path}] + captioned)
        FileUtils.rm_rf(staging_dir)
        out_path
      end

      def run_zip(argv)
        _out, err, status = Open3.capture3("zip", *argv)
        raise Error, "zip failed: #{err.to_s.lines.last.to_s.strip}" unless status.success?

        true
      end
    end
  end
end
