# frozen_string_literal: true

require "fileutils"

module Master
  module Reach
    module SocialSim
      # Optional repligen avatars + postpro feed polish (sandbox paths only).
      module Visuals
        class Error < StandardError; end

        module_function

        def generate_feed!(run_dir:, lora_id: nil, root: Master::ROOT)
          Guard.assert_sandbox!(run_dir: run_dir)
          state = Inbox.load(run_dir)
          avatar_dir = File.join(run_dir, "avatars")
          FileUtils.mkdir_p(avatar_dir)

          token = ReplicateClient.load_token
          raise Error, "REPLICATE_API_TOKEN required for avatar generation" if token.to_s.strip.empty?

          client = ReplicateClient.new(token: token)
          results = []
          state[:npcs].each_value do |npc|
            prompt = "portrait avatar, #{npc[:archetype]}, social media profile photo, cinematic"
            input = { prompt: prompt, aspect_ratio: "1:1", output_format: "png", output_quality: 90 }
            input[:lora] = lora_id if lora_id && !lora_id.to_s.strip.empty?
            url = first_url(client.predict("black-forest-labs/flux-1.1-pro", input, timeout: 300))
            dest = File.join(avatar_dir, "#{npc[:id]}.png")
            VideoPost.download_url(url, dest)
            results << dest
          end

          subject = state[:subject]
          if subject[:avatar_prompt].to_s.strip != ""
            input = {
              prompt: subject[:avatar_prompt],
              aspect_ratio: "1:1",
              output_format: "png",
              output_quality: 90,
            }
            input[:lora] = lora_id if lora_id && !lora_id.to_s.strip.empty?
            url = first_url(client.predict("black-forest-labs/flux-1.1-pro", input, timeout: 300))
            dest = File.join(avatar_dir, "subject_#{subject[:id]}.png")
            VideoPost.download_url(url, dest)
            results << dest
          end

          { avatar_dir: avatar_dir, files: results }
        rescue ArgumentError, StandardError => e
          raise Error, e.message
        end

        def grade_feed!(run_dir:, preset: "social", stock: "kodak_portra", root: Master::ROOT)
          Guard.assert_sandbox!(run_dir: run_dir)
          avatar_dir = File.join(run_dir, "avatars")
          raise Error, "no avatars — run visuals generate first" unless File.directory?(avatar_dir)

          graded_dir = File.join(run_dir, "feed_graded")
          FileUtils.mkdir_p(graded_dir)
          postpro = File.join(Master::DEPLOY_ROOT, "postpro", "postpro.rb")
          raise Error, "postpro.rb missing" unless File.exist?(postpro)

          outputs = []
          Dir.glob(File.join(avatar_dir, "*.png")).each do |src|
            dest = File.join(graded_dir, File.basename(src, ".png") + ".jpg")
            ok = system(
              "ruby", postpro, "--input", src, "--output", dest,
              "--preset", preset.to_s, "--stock", stock.to_s,
              chdir: File.dirname(postpro)
            )
            outputs << dest if ok && File.exist?(dest)
          end
          { graded_dir: graded_dir, files: outputs }
        end

        def first_url(output)
          url = output.is_a?(Array) ? output.first : output
          raise Error, "prediction returned no URL" unless url.is_a?(String) && url.start_with?("http")

          url
        end
      end
    end
  end
end
