# frozen_string_literal: true

require "fileutils"
require "json"
require "time"

module Master
  module Reach
    # Stage character LoRA under DEPLOY/repligen/lora/<name>/ (see lora/README.md).
    module CharacterLoraDataset
      IMAGE_SUFFIXES = %w[.jpg .jpeg .png .webp .gif .bmp].freeze
      VIDEO_SUFFIXES = %w[.mp4 .mov .webm .mkv].freeze
      RECOMMENDED_MIN = CharacterLoraZip::RECOMMENDED_MIN
      RECOMMENDED_MAX = CharacterLoraZip::RECOMMENDED_MAX

      class Error < StandardError; end

      module_function

      def training_dir(name, root: Master::ROOT)
        Master.deploy_path("repligen", "lora", name.to_s)
      end

      def train_dir(name, root: Master::ROOT) = File.join(training_dir(name, root: root), "train")

      def cache_dir(name, root: Master::ROOT) = File.join(training_dir(name, root: root), ".cache")

      def exports_dir(name, root: Master::ROOT) = File.join(training_dir(name, root: root), "exports")

      def sources_dir(name, root: Master::ROOT) = File.join(training_dir(name, root: root), "sources")

      def prepare(
        name:,
        sources:,
        trigger_word: nil,
        split_videos: true,
        frames_per_video: nil,
        max_images: RECOMMENDED_MAX,
        min_images: RECOMMENDED_MIN,
        use_all_frames: false,
        exclude: [],
        subject: "woman",
        root: Master::ROOT
      )
        raise Error, "name required" if name.to_s.strip.empty?
        raise Error, "no sources" if Array(sources).empty?

        trigger_word = trigger_word.to_s.strip
        trigger_word = name.to_s if trigger_word.empty?

        out_dir = training_dir(name, root: root)
        train = train_dir(name, root: root)
        FileUtils.mkdir_p(train)

        excluded = Array(exclude).map { |path| File.expand_path(path) }
        pool = []
        source_entries = []

        Array(sources).each do |source|
          path = File.expand_path(source)
          raise Error, "missing source: #{source}" unless File.exist?(path)

          if excluded.include?(path)
            source_entries << { rel: rel_to(out_dir, path), skipped: "excluded" }
            next
          end

          if video_path?(path)
            frame_dir = File.join(cache_dir(name, root: root), "frames", File.basename(path, ".*"))
            frames = extract_video_frames(path, frame_dir, split_videos: split_videos, frames_per_video: frames_per_video)
            source_entries << {
              rel: rel_to(out_dir, path),
              type: "video",
              extracted_frames: frames.size,
              mode: video_split_mode(split_videos, frames_per_video),
            }
            pool.concat(frames)
          elsif image_path?(path)
            pool << path
            source_entries << { rel: rel_to(out_dir, path), type: "image" }
          else
            raise Error, "unsupported source type: #{path}"
          end
        end

        raise Error, "no images collected" if pool.empty?

        curated = use_all_frames ? pool : curate_images(pool, min_images: min_images, max_images: max_images)
        CharacterLoraLocal.prepare_dataset(curated, train, trigger_word: trigger_word)

        meta = {
          name: name.to_s,
          type: "character",
          trigger_word: trigger_word,
          subject: subject,
          train_dir: "train",
          sources: source_entries,
          extracted_images: pool.size,
          curated_images: curated.size,
          curation: use_all_frames ? "all" : "even_sample",
          created_at: Time.now.utc.iso8601,
        }
        File.write(File.join(out_dir, "meta.json"), JSON.pretty_generate(meta))

        {
          dir: train,
          out_dir: out_dir,
          count: curated.size,
          extracted_count: pool.size,
          trigger_word: trigger_word,
          meta: meta,
        }
      rescue StandardError => e
        raise Error, e.message
      end

      def rel_to(base, path)
        expanded = File.expand_path(path)
        base_exp = File.expand_path(base)
        return expanded.sub("#{base_exp}/", "") if expanded.start_with?("#{base_exp}/")

        expanded
      end

      def extract_video_frames(path, frame_dir, split_videos:, frames_per_video:)
        if frames_per_video.to_i.positive?
          return VideoPost.extract_keyframes(path, frame_dir, count: frames_per_video.to_i)
        end
        return VideoPost.extract_all_frames(path, frame_dir) if split_videos

        VideoPost.extract_keyframes(path, frame_dir, count: 8)
      end

      def video_split_mode(split_videos, frames_per_video)
        return "sample_#{frames_per_video}" if frames_per_video.to_i.positive?
        return "all_frames" if split_videos

        "sample_8"
      end

      def curate_images(images, min_images:, max_images:)
        unique = images.uniq { |path| File.expand_path(path) }
        return unique if unique.size <= max_images

        evenly_sample(unique, max_images)
      end

      def evenly_sample(images, count)
        return images if images.size <= count

        step = images.size.to_f / count
        (0...count).map { |index| images[(index * step).floor] }.uniq
      end

      def image_path?(path)
        IMAGE_SUFFIXES.include?(File.extname(path).downcase)
      end

      def video_path?(path)
        VIDEO_SUFFIXES.include?(File.extname(path).downcase)
      end
    end
  end
end