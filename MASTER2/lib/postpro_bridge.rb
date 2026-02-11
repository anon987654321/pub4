# frozen_string_literal: true

module MASTER
  # Postpro Bridge - Post-processing and enhancement utilities
  # Provides image and video enhancement capabilities
  module PostproBridge
    extend self

    # Film stock presets with recomb matrices
    FILM_STOCKS = {
      kodak_portra_400: {
        matrix: [[1.05, 0.02, -0.07], [-0.01, 1.03, -0.02], [0.01, -0.02, 1.01]],
        grain: 0.2,
        halation: 0.15
      },
      kodak_vision3_500t: {
        matrix: [[0.98, 0.05, -0.03], [0.02, 1.02, -0.04], [-0.01, 0.03, 1.08]],
        grain: 0.3,
        halation: 0.2
      },
      fuji_pro_400h: {
        matrix: [[1.02, 0.03, -0.05], [-0.02, 1.05, -0.03], [0.01, -0.01, 1.00]],
        grain: 0.15,
        halation: 0.12
      },
      kodak_ektar_100: {
        matrix: [[1.08, 0.01, -0.09], [-0.03, 1.06, -0.03], [0.02, -0.03, 1.01]],
        grain: 0.1,
        halation: 0.1
      },
      fuji_velvia_50: {
        matrix: [[1.15, -0.05, -0.10], [-0.05, 1.10, -0.05], [0.03, -0.05, 1.12]],
        grain: 0.08,
        halation: 0.08
      },
      cinestill_800t: {
        matrix: [[0.95, 0.08, -0.03], [0.03, 1.00, -0.03], [-0.02, 0.05, 1.12]],
        grain: 0.35,
        halation: 0.3
      }
    }.freeze

    # Enhancement operations
    OPERATIONS = {
      upscale: {
        name: "Upscale 4x",
        models: ["nightmareai/real-esrgan", "lucataco/clarity-upscaler"]
      },
      face_restore: {
        name: "Face Restoration",
        models: ["tencentarc/gfpgan", "sczhou/codeformer"]
      },
      denoise: {
        name: "Denoise",
        description: "Remove noise from images"
      },
      color_grade: {
        name: "Color Grading",
        description: "Apply color grading presets"
      },
      sharpen: {
        name: "Sharpen",
        description: "Enhance image sharpness"
      }
    }.freeze

    # Apply enhancement to image
    def enhance(image_url:, operation:, params: {})
      return Result.err("Unknown operation: #{operation}") unless OPERATIONS.key?(operation.to_sym)
      
      op = OPERATIONS[operation.to_sym]
      
      if op[:models]
        # Use Replicate model
        model = op[:models].first
        return Result.err("Replicate not available") unless defined?(Replicate) && Replicate.available?
        
        Replicate.generate(
          prompt: "",
          model: model,
          params: { image: image_url }.merge(params)
        )
      else
        # Local processing (placeholder)
        Result.err("Local processing not yet implemented for #{operation}")
      end
    end

    # Batch enhance multiple images
    def batch_enhance(image_urls:, operation:, params: {})
      results = []
      
      image_urls.each do |url|
        result = enhance(image_url: url, operation: operation, params: params)
        results << { url: url, result: result }
      end
      
      Result.ok(results)
    end

    # List available operations
    def operations
      OPERATIONS.map do |key, op|
        {
          id: key,
          name: op[:name],
          description: op[:description] || op[:name],
          models: op[:models]
        }
      end
    end

    # Upscale shortcut
    def upscale(image_url:, scale: 4, model: nil)
      model_id = model || OPERATIONS[:upscale][:models].first
      
      return Result.err("Replicate not available") unless defined?(Replicate) && Replicate.available?
      
      Replicate.generate(
        prompt: "",
        model: model_id,
        params: { image: image_url, scale: scale }
      )
    end

    # Face restoration shortcut
    def restore_face(image_url:, model: nil)
      model_id = model || OPERATIONS[:face_restore][:models].first
      
      return Result.err("Replicate not available") unless defined?(Replicate) && Replicate.available?
      
      Replicate.generate(
        prompt: "",
        model: model_id,
        params: { image: image_url }
      )
    end

    # Check if ruby-vips is available
    def vips_available?
      @vips_available ||= begin
        require 'vips'
        true
      rescue LoadError
        false
      end
    end

    # Film grain synthesis using Vips
    def add_grain(image_path:, intensity: 0.2, output_path: nil)
      return Result.err("ruby-vips not available") unless vips_available?
      
      begin
        require 'vips'
        img = Vips::Image.new_from_file(image_path)
        
        # Generate gaussian noise
        noise = Vips::Image.gaussnoise(img.width, img.height, mean: 128, sigma: intensity * 50)
        
        # Composite with soft-light blend
        result = img.composite([noise], :soft_light)
        
        out = output_path || image_path.sub(/(\.\w+)$/, '_grain\1')
        result.write_to_file(out)
        
        Result.ok(out)
      rescue => e
        Result.err("Grain synthesis failed: #{e.message}")
      end
    end

    # Halation (highlight bloom)
    def add_halation(image_path:, intensity: 0.15, tint: [255, 200, 180], output_path: nil)
      return Result.err("ruby-vips not available") unless vips_available?
      
      begin
        require 'vips'
        img = Vips::Image.new_from_file(image_path)
        
        # Extract highlights
        gray = img.colourspace(:b_w)
        highlights = gray > (255 * 0.7)
        
        # Blur highlights
        bloom = highlights.gaussblur(15)
        
        # Tint the bloom
        tinted = bloom.bandjoin([bloom, bloom])
        tinted = tinted.linear([tint[0]/255.0, tint[1]/255.0, tint[2]/255.0], [0, 0, 0])
        
        # Composite
        result = img + (tinted * intensity)
        
        out = output_path || image_path.sub(/(\.\w+)$/, '_halation\1')
        result.write_to_file(out)
        
        Result.ok(out)
      rescue => e
        Result.err("Halation failed: #{e.message}")
      end
    end

    # Color grading with film stock presets
    def color_grade(image_path:, preset: :kodak_portra_400, output_path: nil)
      return Result.err("ruby-vips not available") unless vips_available?
      return Result.err("Unknown preset: #{preset}") unless FILM_STOCKS.key?(preset)
      
      begin
        require 'vips'
        img = Vips::Image.new_from_file(image_path)
        stock = FILM_STOCKS[preset]
        
        # Apply 3x3 recomb matrix
        result = img.recomb(stock[:matrix])
        
        out = output_path || image_path.sub(/(\.\w+)$/, "_#{preset}\\1")
        result.write_to_file(out)
        
        Result.ok(out)
      rescue => e
        Result.err("Color grading failed: #{e.message}")
      end
    end

    # Chromatic aberration
    def add_chromatic_aberration(image_path:, offset: 2, output_path: nil)
      return Result.err("ruby-vips not available") unless vips_available?
      
      begin
        require 'vips'
        img = Vips::Image.new_from_file(image_path)
        
        # Split channels
        bands = img.bandsplit
        r, g, b = bands[0], bands[1], bands[2]
        
        # Shift red and blue channels
        r_shifted = r.affine([1, 0, 0, 1], oarea: [offset, 0, r.width, r.height])
        b_shifted = b.affine([1, 0, 0, 1], oarea: [-offset, 0, b.width, b.height])
        
        # Recombine
        result = r_shifted.bandjoin([g, b_shifted])
        
        out = output_path || image_path.sub(/(\.\w+)$/, '_chromatic\1')
        result.write_to_file(out)
        
        Result.ok(out)
      rescue => e
        Result.err("Chromatic aberration failed: #{e.message}")
      end
    end

    # Vignette effect
    def add_vignette(image_path:, intensity: 0.5, output_path: nil)
      return Result.err("ruby-vips not available") unless vips_available?
      
      begin
        require 'vips'
        img = Vips::Image.new_from_file(image_path)
        
        # Create radial gradient
        w, h = img.width, img.height
        cx, cy = w / 2.0, h / 2.0
        max_r = Math.sqrt(cx * cx + cy * cy)
        
        # Generate XY coordinate images
        index = Vips::Image.xyz(w, h)
        x = index[0] - cx
        y = index[1] - cy
        r = (x * x + y * y).pow(0.5)
        
        # Create vignette mask
        mask = 1 - ((r / max_r) * intensity).clip(0, 1)
        
        # Apply
        result = img * mask
        
        out = output_path || image_path.sub(/(\.\w+)$/, '_vignette\1')
        result.write_to_file(out)
        
        Result.ok(out)
      rescue => e
        Result.err("Vignette failed: #{e.message}")
      end
    end

    # Light leaks
    def add_light_leaks(image_path:, intensity: 0.3, color: [255, 180, 120], output_path: nil)
      return Result.err("ruby-vips not available") unless vips_available?
      
      begin
        require 'vips'
        img = Vips::Image.new_from_file(image_path)
        
        # Create gradient overlay
        w, h = img.width, img.height
        gradient = Vips::Image.xyz(w, h)[0] / w.to_f
        
        # Tint the gradient
        leak = Vips::Image.black(w, h).bandjoin([Vips::Image.black(w, h), Vips::Image.black(w, h)])
        leak = leak + gradient.bandjoin([gradient, gradient]) * [color[0], color[1], color[2]]
        
        # Screen blend (approximation: A + B - A*B)
        result = img + (leak * intensity)
        
        out = output_path || image_path.sub(/(\.\w+)$/, '_lightleak\1')
        result.write_to_file(out)
        
        Result.ok(out)
      rescue => e
        Result.err("Light leak failed: #{e.message}")
      end
    end

    # Full film stock pipeline
    def apply_film_stock(image_path:, preset: :kodak_portra_400, output_path: nil)
      return Result.err("ruby-vips not available") unless vips_available?
      return Result.err("Unknown preset: #{preset}") unless FILM_STOCKS.key?(preset)
      
      begin
        stock = FILM_STOCKS[preset]
        temp_dir = "/tmp/postpro_#{Time.now.to_i}_#{Process.pid}"
        Dir.mkdir(temp_dir) unless Dir.exist?(temp_dir)
        
        # Step 1: Color grade
        step1 = File.join(temp_dir, "step1.jpg")
        color_grade(image_path: image_path, preset: preset, output_path: step1)
        
        # Step 2: Grain
        step2 = File.join(temp_dir, "step2.jpg")
        add_grain(image_path: step1, intensity: stock[:grain], output_path: step2)
        
        # Step 3: Halation
        step3 = File.join(temp_dir, "step3.jpg")
        add_halation(image_path: step2, intensity: stock[:halation], output_path: step3)
        
        # Step 4: Vignette
        final = output_path || image_path.sub(/(\.\w+)$/, "_film_#{preset}\\1")
        add_vignette(image_path: step3, intensity: 0.3, output_path: final)
        
        # Cleanup
        FileUtils.rm_rf(temp_dir)
        
        Result.ok(final)
      rescue => e
        Result.err("Film stock pipeline failed: #{e.message}")
      end
    end

    # Check if ffmpeg is available
    def ffmpeg_available?
      @ffmpeg_available ||= system("which ffmpeg > /dev/null 2>&1")
    end

    # Video frame processing via ffmpeg
    def process_video_frames(video_path:, processor:, output_path: nil)
      return Result.err("ruby-vips not available") unless vips_available?
      return Result.err("ffmpeg not available") unless ffmpeg_available?
      
      begin
        temp_dir = "/tmp/video_frames_#{Time.now.to_i}_#{Process.pid}"
        Dir.mkdir(temp_dir)
        
        # Extract frames
        system("ffmpeg -i '#{video_path}' '#{temp_dir}/frame_%04d.png' 2>/dev/null")
        
        # Process each frame
        Dir.glob("#{temp_dir}/frame_*.png").sort.each do |frame|
          processor.call(frame, frame)
        end
        
        # Reassemble
        out = output_path || video_path.sub(/(\.\w+)$/, '_processed\1')
        system("ffmpeg -framerate 30 -i '#{temp_dir}/frame_%04d.png' -c:v libx264 -pix_fmt yuv420p '#{out}' 2>/dev/null")
        
        # Cleanup
        FileUtils.rm_rf(temp_dir)
        
        Result.ok(out)
      rescue => e
        Result.err("Video processing failed: #{e.message}")
      end
    end
  end
end
