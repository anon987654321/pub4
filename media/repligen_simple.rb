#!/usr/bin/env ruby
# Repligen v11.1 - RA2 Beach Volleyball Transformation
require "net/http"
require "json"
require "fileutils"

STYLE = "shot on ARRI Alexa Mini LF, ARRI Signature Prime 47mm T1.8, cinematic lighting, shallow depth of field, natural skin tones"

class Repligen
  def initialize
    @token = ENV["REPLICATE_API_TOKEN"] or (puts "Set TOKEN"; exit 1)
    @out = File.join(File.dirname(__FILE__), "repligen")
    FileUtils.mkdir_p(@out)
  end
  
  def api(m, p, b = nil)
    u = URI("https://api.replicate.com/v1#{p}")
    r = m == :get ? Net::HTTP::Get.new(u) : Net::HTTP::Post.new(u)
    r["Authorization"] = "Token #{@token}"
    r["Content-Type"] = "application/json"
    r.body = b.to_json if b
    Net::HTTP.start(u.hostname, u.port, use_ssl: true) { |h| h.request(r) }
  end
  
  def wait(id, n)
    puts "⏳ #{n}..."
    loop do
      sleep 3
      d = JSON.parse(api(:get, "/predictions/#{id}").body)
      case d["status"]
      when "succeeded" then (puts "✓"; return d["output"].is_a?(Array) ? d["output"][0] : d["output"])
      when "failed" then (puts "✗"; return nil)
      else print "."
      end
    end
  end
  
  def run(prompt)
    puts "\n🎬 REPLIGEN v11.1 - RA2 Beach Volleyball"
    puts "Output: #{@out}\\"
    
    enhanced = "#{prompt}, #{STYLE}"
    puts "Prompt: #{enhanced[0..90]}..."
    
    # RA2
    puts "\n[1/2] RA2..."
    res = api(:post, "/predictions", {version: "387d19ad57699a915fbb12f89e61ffae24a2b04a3d5f065b59281e929d533ae5", input: {prompt: enhanced, aspect_ratio: "16:9", output_format: "webp", num_inference_steps: 50}})
    img = wait(JSON.parse(res.body)["id"], "RA2") or return
    
    # Kling
    puts "\n[2/2] Kling 15s..."
    res = api(:post, "/models/lucataco/kling-video/predictions", {version: "latest", input: {image: img, duration: 15, aspect_ratio: "16:9"}})
    vid = wait(JSON.parse(res.body)["id"], "Kling") or return
    
    fn = File.join(@out, "ra2_beach_#{Time.now.strftime("%H%M%S")}.mp4")
    puts "\n📥 #{fn}..."
    system("curl", "-s", "-o", fn, vid)
    
    puts "\n✨ DONE! #{fn} | 15s | $0.52"
    puts "\nFor analog film:"
    puts "  scp #{fn} dev@185.52.176.18:/home/dev/raw/"
    puts "  ssh dev@185.52.176.18 'ruby postpro.rb --video raw/#{File.basename(fn)} --preset blockbuster'"
  end
end

Repligen.new.run(ARGV[0] || "RA2 woman beach volleyball")
