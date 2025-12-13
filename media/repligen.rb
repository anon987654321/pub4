#!/usr/bin/env ruby
# Repligen 10.2 - Multi-Model Chain Orchestrator
# Chain together models for unprecedented motion graphics

require "net/http"
require "json"
require "time"

VERSION = "10.2.0"

# Model Registry with Input/Output Types
MODELS = {
  ra2: {v: "387d19ad57699a915fbb12f89e61ffae24a2b04a3d5f065b59281e929d533ae5", c: 0.02, in: :text, out: :img},
  svd: {v: "d68b6e09eedbac7a49e3d8644999d93579c386a083768235cabca88796d70d82", c: 0.10, in: :img, out: :vid}
}

# Creative Chains
CHAINS = {
  quick: [:ra2],
  motion: [:ra2, :svd],
  chaos: -> { [:ra2, :svd].sample(rand(1..2)) }
}

class Repligen
  def initialize
    @token = ENV["REPLICATE_API_TOKEN"] or (puts "Set REPLICATE_API_TOKEN"; exit 1)
    @db = File.exist?("sessions.json") ? JSON.parse(File.read("sessions.json")) : {"sessions" => []}
  end
  
  def save; File.write("sessions.json", JSON.pretty_generate(@db)); end
  
  def api(method, path, body = nil)
    uri = URI("https://api.replicate.com/v1#{path}")
    req = method == :get ? Net::HTTP::Get.new(uri) : Net::HTTP::Post.new(uri)
    req["Authorization"] = "Token #{@token}"
    req["Content-Type"] = "application/json"
    req.body = body.to_json if body
    Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) { |http| http.request(req) }
  end
  
  def wait(id, name)
    puts "\n⏳ #{name}..."
    loop do
      sleep 3
      data = JSON.parse(api(:get, "/predictions/#{id}").body)
      case data["status"]
      when "succeeded"
        puts "\n✓"
        return data["output"].is_a?(Array) ? data["output"][0] : data["output"]
      when "failed"
        puts "\n✗ #{data["error"]}"
        return nil
      else
        print "."
      end
    end
  end
  
  def gen_img(prompt, sid)
    puts "\n🎨 RA2"
    res = api(:post, "/predictions", {version: MODELS[:ra2][:v], input: {prompt: "RA2 #{prompt}", aspect_ratio: "16:9", output_format: "webp", num_inference_steps: 50}})
    data = JSON.parse(res.body)
    return nil if res.code != "201"
    wait(data["id"], "RA2")
  end
  
  def gen_vid(img, sid)
    puts "\n🎬 SVD"
    res = api(:post, "/predictions", {version: MODELS[:svd][:v], input: {input_image: img, sizing_strategy: "maintain_aspect_ratio", frames_per_second: 6, motion_bucket_id: 127}})
    data = JSON.parse(res.body)
    return nil if res.code != "201"
    wait(data["id"], "SVD")
  end
  
  def chain(name, prompt)
    ch = CHAINS[name]
    ch = ch.call if ch.respond_to?(:call)
    
    puts "\n" + "="*70
    puts "🎬 CHAIN: #{name.upcase} | #{ch.join(' → ')}"
    puts "="*70
    
    sid = @db["sessions"].size + 1
    @db["sessions"] << {id: sid, chain: name.to_s, prompt: prompt, cost: ch.map{|m| MODELS[m][:c]}.sum, t: Time.now.to_i}
    save
    
    out = prompt
    ch.each do |m|
      out = case m
            when :ra2 then gen_img(out, sid)
            when :svd then gen_vid(out, sid)
            end or return
    end
    
    ext = ch.last == :svd ? "mp4" : "webp"
    fn = "#{name}_#{Time.now.strftime("%Y%m%d_%H%M%S")}.#{ext}"
    puts "\n📥 Download..."
    system("curl", "-s", "-o", fn, out)
    
    puts "📤 Upload to VPS..."
    system("scp", "-i", "G:\\priv\\passwd\\id_rsa", "-o", "StrictHostKeyChecking=no", fn, "dev@185.52.176.18:/home/dev/")
    
    puts "\n" + "="*70
    puts "✨ #{sid} | #{fn} | $#{ch.map{|m| MODELS[m][:c]}.sum.round(3)}"
    puts "="*70
  end
  
  def run(args)
    if args.empty?
      puts "Chains: #{CHAINS.keys.join(', ')}"
      exit
    end
    chain(args[0].to_sym, args[1..-1].join(" "))
  end
end

Repligen.new.run(ARGV) if __FILE__ == $0
