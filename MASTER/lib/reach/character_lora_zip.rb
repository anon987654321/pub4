# frozen_string_literal: true

require "fileutils"
require "open3"
require "set"

module Master
  module Reach
    # Caption-named image zips for ostris/flux-dev-lora-trainer (mirrors DEPLOY/tools/repligen Zipper).
    module CharacterLoraZip
      IMAGE_GLOB = "*.{jpg,jpeg,JPG,JPEG,png,PNG,webp,WEBP}".freeze
      RECOMMENDED_MIN = 12
      RECOMMENDED_MAX = 70
      LEGACY_SWEET_SPOT_MAX = 18

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
        images.each_with_index.flat_map do |src, index|
          ext = File.extname(src).downcase
          ext = ".jpg" if ext.empty?
          base = format("a_photo_of_%s_%02d", trigger_word, index + 1)
          dest = File.join(staging_dir, "#{base}#{ext}")
          caption_dest = File.join(staging_dir, "#{base}.txt")
          FileUtils.cp(src, dest)
          caption = caption_for(src, trigger_word: trigger_word)
          File.write(caption_dest, caption)
          [dest, caption_dest]
        end
      end

      def caption_for(image_path, trigger_word:)
        sidecar = caption_path_for(image_path)
        caption = File.exist?(sidecar) ? File.read(sidecar).strip : ""
        caption.empty? ? "a photo of #{trigger_word}" : caption
      end

      def validate(photos_dir, trigger_word: "subjectxyz")
        images = collect_images(photos_dir)
        issues = []
        warnings = []

        issues << "no images in #{photos_dir}" if images.empty?
        if images.size.positive? && images.size < RECOMMENDED_MIN
          warnings << "only #{images.size} images (Replicate recommends #{RECOMMENDED_MIN}-#{RECOMMENDED_MAX} for character LoRAs)"
        end
        warnings << "#{images.size} images exceeds conservative #{LEGACY_SWEET_SPOT_MAX}-image set; prefer manual/ranked curation" if images.size > LEGACY_SWEET_SPOT_MAX
        warnings << "#{images.size} images exceeds v2 #{RECOMMENDED_MAX}-image ceiling" if images.size > RECOMMENDED_MAX

        images.each do |path|
          size = File.size(path)
          warnings << "#{File.basename(path)} is only #{size} bytes — may be too small" if size < 20_000
          dims = image_dimensions(path)
          if dims
            width, height = dims
            warnings << "#{File.basename(path)} is low resolution (#{width}x#{height})" if [width, height].min < 512
          end
        end

        caption_report = audit_captions(photos_dir, trigger_word: trigger_word, images: images)
        warnings.concat(caption_report[:warnings])

        { images: images, issues: issues, warnings: warnings, trigger_word: trigger_word }
      end

      def caption_path_for(image_path)
        File.join(File.dirname(image_path), "#{File.basename(image_path, '.*')}.txt")
      end

      def collect_captions(photos_dir, images: nil)
        image_list = images || collect_images(photos_dir)
        image_list.to_h do |image|
          caption_path = caption_path_for(image)
          [image, File.exist?(caption_path) ? File.read(caption_path).strip : nil]
        end
      end

      def audit_captions(photos_dir, trigger_word:, images: nil)
        captions = collect_captions(photos_dir, images: images)
        warnings = []
        missing = captions.select { |_image, caption| caption.to_s.empty? }.keys
        warnings << "#{missing.size} images missing caption sidecars" if missing.any?

        present = captions.values.compact.map(&:strip).reject(&:empty?)
        unique = present.to_set
        if present.size > 1 && unique.size == 1
          warnings << "all captions are identical; v2 realism needs image-specific captions"
        end

        weak = present.count { |caption| caption.split(/\s+/).size <= 5 }
        warnings << "#{weak} captions are very short; add angle, crop, light, expression, and camera language" if weak.positive?

        missing_trigger = present.count { |caption| !caption.downcase.include?(trigger_word.to_s.downcase) }
        warnings << "#{missing_trigger} captions do not include trigger '#{trigger_word}'" if trigger_word.to_s != "" && missing_trigger.positive?

        { warnings: warnings, captions: captions }
      end

      def image_dimensions(path)
        out, _err, status = Master::Reach::Exec.capture3("identify", "-format", "%w %h", path.to_s)
        return nil unless status.success?

        width, height = out.split.map(&:to_i)
        return nil unless width.positive? && height.positive?

        [width, height]
      rescue Errno::ENOENT
        nil
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
        _out, err, status = Master::Reach::Exec.capture3("zip", *argv)
        raise Error, "zip failed: #{err.to_s.lines.last.to_s.strip}" unless status.success?

        true
      end
    end
  end
end
