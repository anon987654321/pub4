#!/usr/bin/env ruby
# frozen_string_literal: true

# ME2 Final - Generate catwalk with custom roadkill audio

require "net/http"

require "json"

require "base64"

TOKEN = "r8_Oru5iWfF9T8jy0iw9FFFuzQHFJiDMNz03ZcHi"

AUDIO = "G:\music\livesets\roadkill Project\roadkill.mp3"

def api(path, body)

  uri = URI("https://api.replicate.com/v1#{path}")

  req = Net::HTTP::Post.new(uri)

  req["Authorization"] = "Token #{TOKEN}"

  req["Content-Type"] = "application/json"

  req.body = body.to_json

  Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) { |http| http.request(req) }

end

def wait_prediction(id, name)

  uri = URI("https://api.replicate.com/v1/predictions/#{id}")

  req = Net::HTTP::Get.new(uri)

  req["Authorization"] = "Token #{TOKEN}"

  print "⏳ #{name}..."

  loop do

    sleep 5

    res = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) { |http| http.request(req) }

    data = JSON.parse(res.body)

    case data["status"]

    when "succeeded"

      puts " ✓"

      output = data["output"]

      return output.is_a?(Array) ? output[0] : output

    when "failed"

      puts " ✗"

      puts "Error: #{data["error"]}"

      return nil

    else

      print "."

    end

  end

end

puts "

" + "=" * 70

puts "  🌟 ME2 CATWALK - COMPLETE PIPELINE WITH CUSTOM AUDIO 🌟"

puts "=" * 70

# Step 1: Generate stunning ME2 image

puts "

🎨 Step 1: Generating haute couture image of ME2..."

res = api("/models/black-forest-labs/flux-pro/predictions", {

  input: {

    prompt: "ME2 beautiful blonde woman with athletic curvy figure in stunning black and gold haute couture evening gown, walking confidently down fashion runway, professional supermodel pose, full body shot, dramatic runway spotlight with soft bokeh background, elegant powerful stride, high-end fashion photography, vogue magazine quality, striking beauty, sharp focus on model, cinematic composition, 16:9 aspect ratio, photorealistic, 8k quality",

    aspect_ratio: "16:9",

    output_format: "webp",

    guidance: 3.5,

    num_inference_steps: 40,

    safety_tolerance: 2

  }

})

image_url = wait_prediction(JSON.parse(res.body)["id"], "Flux Pro Image")

exit unless image_url

image_file = "me2_img_#{Time.now.to_i}.webp"

File.write(image_file, Net::HTTP.get(URI(image_url)))

puts "✓ Image saved: #{image_file}"

# Step 2: Animate to video

puts "

🎬 Step 2: Animating runway walk (10 seconds)..."

res = api("/models/minimax/video-01/predictions", {

  input: {

    prompt: "Beautiful blonde model in haute couture gown walking powerfully down runway, confident supermodel stride, smooth elegant motion, fashion show cinematography",

    first_frame_image: image_url,

    prompt_optimizer: true

  }

})

video_url = wait_prediction(JSON.parse(res.body)["id"], "Minimax Video 10s")

exit unless video_url

video_file = "me2_video_#{Time.now.to_i}.mp4"

File.write(video_file, Net::HTTP.get(URI(video_url)))

puts "✓ Video saved: #{video_file}"

# Step 3: Add custom audio

if File.exist?(AUDIO)

  puts "

🎵 Step 3: Adding your custom roadkill beat..."

  final_file = "me2_catwalk_ROADKILL_#{Time.now.to_i}.mp4"

  cmd = "ffmpeg -i "#{video_file}" -i "#{AUDIO}" -c:v copy -map 0:v:0 -map 1:a:0 -shortest "#{final_file}" -y 2>&1"

  output = `#{cmd}`

  if File.exist?(final_file)

    puts "✓ Final video with audio: #{final_file}"

    puts "

" + "=" * 70

    puts "  ✨ COMPLETE! ME2 looking fly on the catwalk with your beat! ✨"

    puts "=" * 70

    puts "

📁 Files created:"

    puts "  Image: #{image_file}"

    puts "  Video (no audio): #{video_file}"

    puts "  Final (with roadkill audio): #{final_file}"

  else

    puts "✗ ffmpeg failed - install with: winget install ffmpeg"

    puts "  Video without audio: #{video_file}"

  end

else

  puts "

⚠  Audio file not found: #{AUDIO}"

  puts "  Video saved: #{video_file}"

end

