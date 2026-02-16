# frozen_string_literal: true

module MASTER
  module Bridges
    # Repligen Bridge - Interface to AI media generation pipeline
    # Based on repligen.rb WILD_CHAIN model catalog
    # Provides access to image, video, and enhancement models
    module RepligenBridge
      extend self

      # Model catalog - delegates to Replicate::MODELS for DRY
      def self.wild_chain
        @wild_chain ||= {
          image_gen: [
            { model: MASTER::Replicate::MODELS[:flux_pro], name: "Flux Pro" },
            { model: MASTER::Replicate::MODELS[:flux_dev], name: "Flux Dev" },
            { model: MASTER::Replicate::MODELS[:sdxl], name: "SDXL" },
            { model: MASTER::Replicate::MODELS[:ideogram_v2], name: "Ideogram V2" },
            { model: MASTER::Replicate::MODELS[:recraft_v3], name: "Recraft V3" }
          ],
          video_gen: [
            { model: MASTER::Replicate::MODELS[:hailuo], name: "Hailuo 2.3" },
            { model: MASTER::Replicate::MODELS[:kling], name: "Kling 2.5" },
            { model: MASTER::Replicate::MODELS[:luma_ray], name: "Luma Ray 2" },
            { model: MASTER::Replicate::MODELS[:wan], name: "WAN 2.5" },
            { model: MASTER::Replicate::MODELS[:sora], name: "Sora 2" }
          ],
          enhance: [
            { model: MASTER::Replicate::MODELS[:esrgan], name: "Real-ESRGAN 4x" },
            { model: MASTER::Replicate::MODELS[:gfpgan], name: "GFPGAN Face" },
            { model: MASTER::Replicate::MODELS[:codeformer], name: "CodeFormer" },
            { model: MASTER::Replicate::MODELS[:clarity], name: "Clarity 4x" }
          ],
          audio: [
            { model: MASTER::Replicate::MODELS[:musicgen], name: "MusicGen" },
            { model: MASTER::Replicate::MODELS[:bark], name: "Bark TTS" }
          ],
          transcribe: [
            { model: MASTER::Replicate::MODELS[:whisper], name: "Whisper" }
          ]
        }.freeze
      end

      # Get all models for a category
      def models_for(category)
        self.class.wild_chain[category.to_sym] || []
      end

      # List all available categories
      def categories
        self.class.wild_chain.keys
      end

      # Generate image using Replicate API
      def generate_image(prompt:, model: nil)
        model_id = model || self.class.wild_chain[:image_gen].first[:model]

        return Result.err("Replicate not available.") unless defined?(Replicate) && Replicate.available?

        Replicate.generate(prompt: prompt, model: model_id)
      end

      # Generate video using Replicate API
      def generate_video(prompt:, model: nil)
        model_id = model || self.class.wild_chain[:video_gen].first[:model]

        return Result.err("Replicate not available.") unless defined?(Replicate) && Replicate.available?

        Replicate.run(model_id: model_id, input: { prompt: prompt })
      end

      # Enhance image using upscaling models
      def enhance_image(image_url:, model: nil)
        model_id = model || self.class.wild_chain[:enhance].first[:model]

        return Result.err("Replicate not available.") unless defined?(Replicate) && Replicate.available?

        Replicate.run(model_id: model_id, input: { image: image_url })
      end

      # Get model info
      def model_info(model_id)
        self.class.wild_chain.each do |category, models|
          models.each do |m|
            return { category: category, **m } if m[:model] == model_id
          end
        end
        nil
      end

      # List all models
      def all_models
        result = []
        self.class.wild_chain.each do |category, models|
          models.each do |m|
            result << { category: category, **m }
          end
        end
        result
      end

      # Catwalk styles and lighting constants
      CATWALK_STYLES = %w[haute_couture streetwear avant_garde minimalist sportswear editorial fantasy cyberpunk].freeze
      CATWALK_LIGHTING = %w[runway studio natural dramatic neon golden cinematic].freeze

      # Wild chain - random creative pipeline combos
      def wild_chain(steps: 3, seed: nil)
        rng = seed ? Random.new(seed) : Random.new

        chain = []
        steps.times do
          # Randomly pick a category (prefer image gen and enhance)
          category = [:image_gen, :enhance, :video_gen].sample(random: rng)
          models = self.class.wild_chain[category]

          next if models.nil? || models.empty?

          model = models.sample(random: rng)
          chain << {
            step: chain.length + 1,
            category: category,
            model: model[:model],
            name: model[:name]
          }
        end

        Result.ok(chain)
      end

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
        model_id = model || self.class.wild_chain[:image_gen].first[:model]

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

        video_model = model || self.class.wild_chain[:video_gen].first[:model]
        image_model = self.class.wild_chain[:image_gen].first[:model]
        results = []

        scenes.each_with_index do |scene, idx|
          # Generate hero image
          img_params = { prompt: scene[:image_prompt] }
          img_params[:lora] = lora if lora
          img_result = Replicate.generate(prompt: scene[:image_prompt], model: image_model, params: img_params)
          next if img_result.err?

          image_url = img_result.value[:urls]&.first || img_result.value[:output]
          next unless image_url

          # Animate to video
          vid_result = Replicate.run(
            model_id: video_model,
            input: { image: image_url, prompt: scene[:video_prompt] || "", duration: scene[:duration] || 10 }
          )

          results << { step: idx + 1, name: scene[:name], image: image_url, video: vid_result.ok? ? vid_result.value[:output] : nil }
        end

        Result.ok(results)
      end

      # Enhance training photos for LoRA (background removal + upscale + face restore)
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
          img_data = File.read(img_path)
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

      # SQLite model index for searching Replicate catalog
      def index_models(db_path: nil)
        return Result.err("Replicate not available.") unless defined?(Replicate) && Replicate.available?

        begin
          require "sqlite3"
        rescue LoadError
          return Result.err("sqlite3 gem not available.")
        end

        db_path ||= File.join(MASTER::Paths.data_dir, "models.db")
        db = SQLite3::Database.new(db_path)

        db.execute <<-SQL
          CREATE TABLE IF NOT EXISTS models (
            id TEXT PRIMARY KEY, owner TEXT, name TEXT,
            description TEXT, run_count INTEGER, category TEXT, indexed_at INTEGER
          )
        SQL

        db.execute <<-SQL
          CREATE TABLE IF NOT EXISTS collections (
            slug TEXT PRIMARY KEY, name TEXT, description TEXT, model_count INTEGER
          )
        SQL

        # Fetch and index via Replicate API
        collections_resp = Replicate.send(:api_request, :get, "/collections") rescue nil
        return Result.err("Failed to fetch collections.") unless collections_resp

        collections = JSON.parse(collections_resp.body)["results"] || []
        total = 0

        collections.each do |coll|
          db.execute("INSERT OR REPLACE INTO collections VALUES (?, ?, ?, ?)",
            [coll["slug"], coll["name"], coll["description"], 0])

          detail = Replicate.send(:api_request, :get, "/collections/#{coll["slug"]}") rescue nil
          next unless detail

          models = JSON.parse(detail.body)["models"] || []
          models.each do |m|
            model_id = "#{m["owner"]}/#{m["name"]}"
            db.execute("INSERT OR REPLACE INTO models VALUES (?, ?, ?, ?, ?, ?, ?)",
              [model_id, m["owner"], m["name"], m["description"], m["run_count"] || 0, coll["slug"], Time.now.to_i])
            total += 1
          end
        end

        db.close
        Result.ok({ db: db_path, models: total, collections: collections.length })
      end
    end
  end
end
