#!/usr/bin/env ruby
# frozen_string_literal: true
# ME2 Catwalk Generator - Create stunning runway videos of ME2
require "net/http"
require "json"
require "fileutils"
TOKEN = ENV["REPLICATE_API_TOKEN"] || raise("Set REPLICATE_API_TOKEN")
class ME2Catwalk
  def initialize
    @token = TOKEN
    @out = File.join(File.dirname(__FILE__), "repligen")
    FileUtils.mkdir_p(@out)
  end
  def api(method, path, body = nil)
    uri = URI("https://api.replicate.com/v1#{path}")
    req = method == :get ? Net::HTTP::Get.new(uri) : Net::HTTP::Post.new(uri)
    req["Authorization"] = "Token #{@token}"
    req["Content-Type"] = "application/json"
    req.body = body.to_json if body
    Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) { |http| http.request(req) }
  end
  def wait(id, name)
    print "⏳ #{name}..."
    loop do
      sleep 3
      res = api(:get, "/predictions/#{id}")
      data = JSON.parse(res.body)
      case data["status"]
      when "succeeded"
        puts " ✓"
        return data["output"].is_a?(Array) ? data["output"][0] : data["output"]
      when "failed"
        puts " ✗ #{data["error"]}"
        return nil
      else
        print "."
      end
    end
  end
  def download(url, filename)
    puts "📥 Downloading..."
    File.write(filename, Net::HTTP.get(URI(url)))
    puts "✓ Saved: #{filename}"
  end
  def generate_catwalk_image(style: "high fashion", lighting: "dramatic runway lighting")
    timestamp = Time.now.strftime("%Y%m%d_%H%M%S")
    # Construct detailed prompt for ME2 on catwalk
    prompt = <<~PROMPT.strip
      ME2 beautiful blonde woman with athletic curvy figure walking confidently down fashion runway,
      #{style} outfit, professional model pose, full body shot, #{lighting},
      elegant powerful stride, designer clothing, catwalk background with audience blur,
      high-end fashion photography, vogue magazine quality, striking beauty,
      sharp focus on model, bokeh background, cinematic composition,
      16:9 aspect ratio, photorealistic, 8k quality
    PROMPT
    puts "
✨ ME2 CATWALK GENERATOR ✨"
    puts "=" * 60
    puts "🎨 Generating image..."
    puts "Style: #{style}"
    puts "Lighting: #{lighting}"
    puts "Prompt: #{prompt[0..150]}..."
    puts "=" * 60
    # Check if ME2 LoRA is trained and available
    # If not, use Flux Pro with ME2 description
    res = api(:post, "/models/black-forest-labs/flux-pro/predictions", {
      input: {
        prompt: prompt,
        aspect_ratio: "16:9",
        output_format: "webp",
        guidance: 3.5,
        num_inference_steps: 40,
        safety_tolerance: 2
      }
    })
    image_url = wait(JSON.parse(res.body)["id"], "Flux Pro Image")
    return nil unless image_url
    filename = File.join(@out, "me2_catwalk_#{timestamp}.webp")
    download(image_url, filename)
    { image_url: image_url, filename: filename }
  end
  def animate_catwalk(image_url, motion: "confident runway walk", audio_path: nil)
    timestamp = Time.now.strftime("%Y%m%d_%H%M%S")
    motion_prompt = <<~PROMPT.strip
      Model walking forward on runway with confident stride,
      smooth catwalk motion, professional model walk,
      elegant movement, camera slowly tracking forward,
      fashion show cinematography, #{motion},
      steady cam movement, high fashion video
    PROMPT
    puts "
🎬 Animating catwalk walk..."
    puts "Motion: #{motion}"
    puts "Audio: #{audio_path ? File.basename(audio_path) : 'None'}"
    puts "=" * 60
    # Use Minimax Hailuo (faster, supports audio)
    res = api(:post, "/models/minimax/video-01/predictions", {
      input: {
        prompt: motion_prompt,
        first_frame_image: image_url,
        prompt_optimizer: true
      }
    })
    video_url = wait(JSON.parse(res.body)["id"], "Minimax Video 10s")
    return nil unless video_url
    filename = File.join(@out, "me2_catwalk_#{timestamp}.mp4")
    download(video_url, filename)
    # Add custom audio if provided
    if audio_path && File.exist?(audio_path)
      final_filename = File.join(@out, "me2_catwalk_#{timestamp}_audio.mp4")
      add_audio_to_video(filename, audio_path, final_filename)
      { video_url: video_url, filename: final_filename, original: filename }
    else
      { video_url: video_url, filename: filename }
    end
  end
  def add_audio_to_video(video_path, audio_path, output_path)
    puts "
🎵 Adding custom audio track..."
    # Use ffmpeg to combine video and audio
    cmd = "ffmpeg -i "#{video_path}" -i "#{audio_path}" -c:v copy -map 0:v:0 -map 1:a:0 -shortest "#{output_path}" -y"
    system(cmd)
    if File.exist?(output_path)
      puts "✓ Audio added: #{output_path}"
      true
    else
      puts "✗ Failed to add audio"
      false
    end
  end
  def generate_full_catwalk(style: "high fashion", lighting: "dramatic runway lighting", motion: "confident runway walk", audio_path: nil)
    puts "
" + "=" * 60
    puts "  🌟 ME2 CATWALK - FULL PIPELINE 🌟"
    puts "=" * 60
    # Step 1: Generate image
    image_result = generate_catwalk_image(style: style, lighting: lighting)
    return unless image_result
    # Step 2: Animate to video
    video_result = animate_catwalk(image_result[:image_url], motion: motion, audio_path: audio_path)
    return unless video_result
    puts "
" + "=" * 60
    puts "  ✨ COMPLETE! ✨"
    puts "=" * 60
    puts "📸 Image: #{image_result[:filename]}"
    puts "🎬 Video: #{video_result[:filename]}"
    puts "=" * 60
    {
      image: image_result,
      video: video_result
    }
  end
end
if __FILE__ == $0
  case ARGV[0]
  when "image"
    style = ARGV[1] || "high fashion"
    lighting = ARGV[2] || "dramatic runway lighting"
    ME2Catwalk.new.generate_catwalk_image(style: style, lighting: lighting)
  when "video"
    image_url = ARGV[1] || raise("Provide image URL as second argument")
    motion = ARGV[2] || "confident runway walk"
    audio_path = ARGV[3]
    ME2Catwalk.new.animate_catwalk(image_url, motion: motion, audio_path: audio_path)
  when "full", nil
    style = ARGV[1] || "haute couture evening gown"
    lighting = ARGV[2] || "dramatic spotlight with bokeh background"
    motion = ARGV[3] || "powerful confident runway walk, slow motion elegance"
    audio_path = ARGV[4]
    ME2Catwalk.new.generate_full_catwalk(style: style, lighting: lighting, motion: motion, audio_path: audio_path)
  else
    puts <<~HELP
      ME2 Catwalk Generator
      Usage:
        ruby me2_catwalk.rb full [style] [lighting] [motion] [audio_path]
        ruby me2_catwalk.rb image [style] [lighting]
        ruby me2_catwalk.rb video [image_url] [motion] [audio_path]
      Examples:
        ruby me2_catwalk.rb full
        ruby me2_catwalk.rb full "designer suit" "golden hour" "elegant walk" "G:\music\track.mp3"
        ruby me2_catwalk.rb image "evening gown" "spotlight"
        ruby me2_catwalk.rb video https://... "elegant stride" "audio.mp3"
      Styles:
        - haute couture evening gown
        - designer business suit
        - avant-garde fashion
        - luxury streetwear
        - red carpet glamour
      Lighting:
        - dramatic runway spotlight
        - golden hour natural light
        - studio fashion lighting
        - bokeh background with rim lighting
        - cinematic blue hour
      Motion:
        - powerful confident runway walk
        - elegant gliding motion
        - fierce model strut
        - slow motion grace
        - dynamic forward movement
    HELP
  end
end
