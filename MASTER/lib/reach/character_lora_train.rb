# frozen_string_literal: true

require "fileutils"

module Master
  module Reach
    # Character Flux LoRA: stage dataset → zip → Replicate ostris/flux-dev-lora-trainer.
    module CharacterLoraTrain
      class Error < StandardError; end

      module_function

      def train(
        name:,
        sources:,
        destination: nil,
        trigger_word: nil,
        split_videos: true,
        frames_per_video: nil,
        max_images: CharacterLoraDataset::RECOMMENDED_MAX,
        min_images: CharacterLoraDataset::RECOMMENDED_MIN,
        use_all_frames: false,
        exclude: [],
        prepare_only: false,
        local: false,
        ai_toolkit_root: nil,
        steps: CharacterLoraLocal::DEFAULT_STEPS,
        rank: CharacterLoraLocal::DEFAULT_RANK,
        subject: "woman",
        root: Master::ROOT,
        replicate: nil
      )
        trigger = trigger_word.to_s.strip
        trigger = name.to_s if trigger.empty?

        dataset = CharacterLoraDataset.prepare(
          name: name,
          sources: sources,
          trigger_word: trigger,
          split_videos: split_videos,
          frames_per_video: frames_per_video,
          max_images: max_images,
          min_images: min_images,
          use_all_frames: use_all_frames,
          exclude: exclude,
          subject: subject,
          root: root
        )
        report = CharacterLoraZip.validate(dataset[:dir], trigger_word: trigger)
        raise Error, report[:issues].join("; ") unless report[:issues].empty?

        exports = CharacterLoraDataset.exports_dir(name, root: root)
        FileUtils.mkdir_p(exports)
        zip_path = File.join(exports, "replicate.zip")
        CharacterLoraZip.zip(dataset[:dir], zip_path, trigger_word: trigger)

        result = {
          name: name.to_s,
          trigger_word: trigger,
          dataset_dir: dataset[:dir],
          out_dir: dataset[:out_dir],
          zip_path: zip_path,
          images: dataset[:count],
          extracted_images: dataset[:extracted_count],
          warnings: report[:warnings],
          destination: destination,
        }

        if local
          local_result = CharacterLoraLocal.bootstrap(
            name: name,
            train_dir: dataset[:dir],
            out_dir: dataset[:out_dir],
            trigger_word: trigger,
            steps: steps,
            rank: rank,
            ai_toolkit_root: ai_toolkit_root,
            subject: subject
          )
          return result.merge(local_result)
        end

        return result if prepare_only

        client = replicate || ReplicateClient.new
        dest = destination.to_s.strip
        dest = default_destination(client, name) if dest.empty?
        zip_url = client.upload_zip(zip_path)
        version = client.train_lora(zip_url, dest, trigger_word: trigger)
        result.merge(destination: dest, version: version, zip_url: zip_url)
      rescue CharacterLoraDataset::Error, CharacterLoraZip::Error, CharacterLoraLocal::Error, ArgumentError => e
        raise Error, e.message
      end

      def default_destination(client, name)
        username = client.account_username
        raise Error, "pass --destination owner/model (could not resolve Replicate username)" if username.empty?

        "#{username}/#{sanitize_model_name(name)}"
      end

      def sanitize_model_name(name)
        name.to_s.downcase.gsub(/[^a-z0-9_-]/, "-").gsub(/-+/, "-").delete_prefix("-").delete_suffix("-")
      end

      def format_result(result)
        lines = [
          "lora-train: name=#{result[:name]} curated=#{result[:images]} extracted=#{result[:extracted_images]} trigger=#{result[:trigger_word]}",
          "root: #{result[:out_dir]}",
          "train: #{result[:dataset_dir]}",
          "cache: #{File.join(result[:out_dir], '.cache/frames')}",
          "zip: #{result[:zip_path]}",
        ]
        result[:warnings]&.each { |warning| lines << "warn: #{warning}" }
        if result[:mode] == :local
          lines.concat(CharacterLoraLocal.format_notes(result))
        elsif result[:destination]
          lines << "destination: #{result[:destination]}"
          lines << "version: #{result[:version]}" if result[:version]
        else
          lines << "prepare_only: upload skipped"
        end
        lines.join("\n")
      end
    end
  end
end
