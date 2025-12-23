#!/usr/bin/env ruby
# frozen_string_literal: true
# ME2 Video + Audio - Streamlined
require "net/http"
require "json"
TOKEN = "r8_Oru5iWfF9T8jy0iw9FFFuzQHFJiDMNz03ZcHi"
IMAGE_URL = "https://replicate.delivery/yhqm/tBDyxJG8Zd6DQvRvnHpZrEQC7tFkDNW8PSzc9WpLxTMGmJlrA/out-0.webp"
AUDIO_PATH = "G:\music\livesets\roadkill Project\roadkill.mp3"
def api(path, body)
  uri = URI("https://api.replicate.com/v1#{path}")
  req = Net::HTTP::Post.new(uri)
  req["Authorization"] = "Token #{TOKEN}"
  req["Content-Type"] = "application/json"
  req.body = body.to_json
  Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) { |http| http.request(req) }
end
def wait_for_video(id)
  uri = URI("https://api.replicate.com/v1/predictions/#{id}")
  req = Net::HTTP::Get.new(uri)
  req["Authorization"] = "Token #{TOKEN}"
  loop do
    sleep 5
    res = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) { |http| http.request(req) }
    data = JSON.parse(res.body)
    case data["status"]
    when "succeeded"
      return data["output"]
    when "failed"
      puts "Failed: #{data["error"]}"
      return nil
    else
      print "."
    end
  end
end
puts "🎬 Generating ME2 catwalk video..."
res = api("/models/minimax/video-01/predictions", {
  input: {
    prompt: "Beautiful blonde woman in haute couture walking confidently down fashion runway, powerful supermodel stride, elegant motion",
    first_frame_image: IMAGE_URL,
    prompt_optimizer: true
  }
})
id = JSON.parse(res.body)["id"]
puts "Prediction ID: #{id}"
video_url = wait_for_video(id)
exit unless video_url
video_file = "me2_catwalk_#{Time.now.to_i}.mp4"
puts "
📥 Downloading..."
File.write(video_file, Net::HTTP.get(URI(video_url)))
puts "✓ Video saved: #{video_file}"
if File.exist?(AUDIO_PATH)
  puts "
🎵 Adding custom audio..."
  output = video_file.gsub(".mp4", "_roadkill.mp4")
  cmd = "ffmpeg -i "#{video_file}" -i "#{AUDIO_PATH}" -c:v copy -map 0:v:0 -map 1:a:0 -shortest "#{output}" -y"
  system(cmd)
  if File.exist?(output)
    puts "✓ Final video: #{output}"
  else
    puts "✗ Audio merge failed (do you have ffmpeg installed?)"
  end
else
  puts "⚠ Audio file not found: #{AUDIO_PATH}"
end
