# frozen_string_literal: true

module MASTER
  module Bridges
    module ReplicateBridge
      # Execute a multi-model pipeline sequentially
      def execute_chain(chain)
        return Result.err("Chain cannot be empty.") if chain.nil? || chain.empty?
        return Result.err("Replicate not available.") unless defined?(Replicate) && Replicate.available?

        results = []
        current_output = nil

        chain.each_with_index do |step, idx|
          params = {}

          # If not first step and previous output exists, use it as input
          if idx > 0 && current_output
            params[:image] = current_output if step[:category] == :enhance
            params[:init_image] = current_output if step[:category] == :image_gen
          end

          # Execute step
          result = Replicate.run(
            model_id: step[:model],
            input: { prompt: step[:prompt] || "" }.merge(params)
          )

          return result if result.err?

          current_output = result.value[:output]
          results << {
            step: idx + 1,
            model: step[:name],
            output: current_output
          }
        end

        Result.ok(results)
      end

      # Generate catwalk fashion image
      def generate_catwalk(prompt:, style: nil, lighting: nil, model: nil)
        style ||= CATWALK_STYLES.sample
        lighting ||= CATWALK_LIGHTING.sample

        return Result.err("Unknown style: #{style}") unless CATWALK_STYLES.include?(style.to_s)
        return Result.err("Unknown lighting: #{lighting}") unless CATWALK_LIGHTING.include?(lighting.to_s)

        full_prompt = "fashion photography, #{style} style, #{lighting} lighting, #{prompt}"
        model_id = model || ReplicateBridge.model_catalog[:image_gen].first[:model]

        return Result.err("Replicate not available.") unless defined?(Replicate) && Replicate.available?

        Replicate.generate(
          prompt: full_prompt,
          model: model_id,
          params: { style: style, lighting: lighting }
        )
      end

      # Search models by keyword
      def search_models(query)
        query_lower = query.to_s.downcase
        matches = []

        self.class.wild_chain.each do |category, models|
          models.each do |m|
            if m[:name].downcase.include?(query_lower) || m[:model].downcase.include?(query_lower)
              matches << { category: category, **m }
            end
          end
        end

        Result.ok(matches)
      end

      # Train LoRA wrapper
      def train_lora(training_data:, trigger_word:, model: "ostris/flux-dev-lora-trainer")
        return Result.err("Replicate not available.") unless defined?(Replicate) && Replicate.available?
        return Result.err("Training data cannot be empty.") if training_data.nil? || training_data.empty?
        return Result.err("Trigger word required.") if trigger_word.nil? || trigger_word.empty?

        Replicate.run(
          model_id: model,
          input: {
            input_images: training_data,
            trigger_word: trigger_word,
            steps: 1000,
            learning_rate: 0.0004
          }
        )
      end

      # Generate commercial video (multi-scene pipeline)
      def generate_commercial(subject:, lora: nil, model: nil, scenes: [])
        return Result.err("Replicate not available.") unless defined?(Replicate) && Replicate.available?
        return Result.err("No scenes provided.") if scenes.empty?

        video_model = model || ReplicateBridge.model_catalog[:video_gen].first[:model]
        image_model = ReplicateBridge.model_catalog[:image_gen].first[:model]
        results = []

        scenes.each_with_index do |scene, idx|
          img_params = { prompt: scene[:image_prompt] }
          img_params[:lora] = lora if lora
          img_result = Replicate.generate(prompt: scene[:image_prompt], model: image_model, params: img_params)
          next if img_result.err?

          image_url = img_result.value[:urls]&.first || img_result.value[:output]
          next unless image_url

          vid_result = Replicate.run(
            model_id: video_model,
            input: { image: image_url, prompt: scene[:video_prompt] || "", duration: scene[:duration] || 10 }
          )

          results << { step: idx + 1, name: scene[:name], image: image_url, video: vid_result.ok? ? vid_result.value[:output] : nil }
        end

        Result.ok(results)
      end

      # Enhance training photos for LoRA
      def enhance_training_photos(input_dir:, output_dir: nil)
        return Result.err("Replicate not available.") unless defined?(Replicate) && Replicate.available?
        return Result.err("Directory not found: #{input_dir}") unless Dir.exist?(input_dir)

        output_dir ||= "#{input_dir}_enhanced"
        FileUtils.mkdir_p(output_dir)

        images = Dir[File.join(input_dir, "*.{jpg,jpeg,png}")].sort
        return Result.err("No images found in #{input_dir}") if images.empty?

        results = []
        images.each_with_index do |img_path, i|
          name = File.basename(img_path, ".*")
          img_data = File.binread(img_path)
          img_url = "data:image/jpeg;base64,#{Base64.strict_encode64(img_data)}"

          enhanced = enhance_image(image_url: img_url)
          next if enhanced.err?

          output_url = enhanced.value[:output] || enhanced.value[:urls]&.first
          next unless output_url

          output_path = File.join(output_dir, "#{name}.png")
          Replicate.download_file(output_url, output_path) if Replicate.respond_to?(:download_file)
          results << { name: name, path: output_path }
        end

        Result.ok({ count: results.length, total: images.length, output_dir: output_dir, files: results })
      end

      # TODO: index_models method removed - used non-existent api_request method
      # Re-implement with proper HTTP requests if needed in the future
    end
  end
end
