#!/usr/bin/env ruby
# frozen_string_literal: true

require "net/http"
require "json"
require "fileutils"
require "time"

VERSION = "10.0.0"

MODELS = {
  ra2: {
    version: "387d19ad57699a915fbb12f89e61ffae24a2b04a3d5f065b59281e929d533ae5",
    cost: 0.02
  },
  svd: {
    version: "d68b6e09eedbac7a49e3d8644999d93579c386a083768235cabca88796d70d82",
    cost: 0.10
  }
}

class Repligen
  attr_reader :token, :db
  
  def initialize
    @token = ENV["REPLICATE_API_TOKEN"]
    setup_database
    recover_pending_jobs
  end
  
  def setup_database
    @db_file = "repligen_sessions.json"
    if File.exist?(@db_file)
      @db = JSON.parse(File.read(@db_file))
    else
      @db = {"sessions" => [], "predictions" => []}
      save_db
    end
  end
  
  def save_db
    File.write(@db_file, JSON.pretty_generate(@db))
  end
  
  def recover_pending_jobs
    pending = @db["sessions"].select { |s| ["image_pending", "video_pending"].include?(s["status"]) }
    return if pending.empty?
    
    puts "\n🔄 Found #{pending.size} pending job(s)"
    pending.each { |s| puts "  [#{s["id"]}] #{s["prompt"][0..50]}... (#{s["status"]})" }
    print "\nResume? (y/n): "
    
    input = STDIN.gets
    return unless input
    
    pending.each { |s| resume_session(s["id"]) } if input.chomp.downcase == 'y'
  end
  
  def api_request(method, path, body = nil)
    uri = URI("https://api.replicate.com/v1#{path}")
    req = (method == :get) ? Net::HTTP::Get.new(uri) : Net::HTTP::Post.new(uri)
    req["Authorization"] = "Token #{@token}"
    req["Content-Type"] = "application/json"
    req.body = body.to_json if body
    Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) { |http| http.request(req) }
  end
  
  def wait_for_prediction(pred_id, sid = nil, name = "model")
    puts "\n⏳ #{name}..."
    loop do
      sleep 3
      res = api_request(:get, "/predictions/#{pred_id}")
      data = JSON.parse(res.body)
      if sid
        pred = @db["predictions"].find { |p| p["id"] == pred_id }
        pred["status"] = data["status"] if pred
        save_db
      end
      case data["status"]
      when "succeeded"
        puts "\n✓ Complete!"
        if sid
          pred = @db["predictions"].find { |p| p["id"] == pred_id }
          pred["output"] = data["output"].is_a?(Array) ? data["output"][0] : data["output"] if pred
          save_db
        end
        return data
      when "failed"
        puts "\n✗ Failed: #{data["error"]}"
        return nil
      when "processing", "starting"
        print "."
      end
    end
  end
  
  def update_session(sid, updates)
    session = @db["sessions"].find { |s| s["id"] == sid }
    return unless session
    updates.each { |k, v| session[k.to_s] = v }
    session["updated_at"] = Time.now.to_i
    save_db
  end
  
  def generate_ra2_image(prompt, sid)
    puts "\n🎨 RA2 image generation"
    puts "Prompt: #{prompt}"
    update_session(sid, status: "image_pending")
    body = { version: MODELS[:ra2][:version], input: { prompt: "RA2 #{prompt}", aspect_ratio: "16:9", output_format: "webp", num_inference_steps: 50 } }
    res = api_request(:post, "/predictions", body)
    data = JSON.parse(res.body)
    return (update_session(sid, status: "image_failed"); nil) if res.code != "201"
    @db["predictions"] << {"id" => data["id"], "session_id" => sid, "model" => "ra2", "status" => "starting", "output" => nil, "created_at" => Time.now.to_i}
    save_db
    result = wait_for_prediction(data["id"], sid, "RA2")
    return nil unless result
    img = result["output"].is_a?(Array) ? result["output"][0] : result["output"]
    update_session(sid, image_url: img, status: "image_complete")
    img
  end
  
  def generate_video(img_url, sid)
    puts "\n🎬 SVD video generation"
    update_session(sid, status: "video_pending")
    body = { version: MODELS[:svd][:version], input: { input_image: img_url, sizing_strategy: "maintain_aspect_ratio", frames_per_second: 6, motion_bucket_id: 127 } }
    res = api_request(:post, "/predictions", body)
    data = JSON.parse(res.body)
    return (update_session(sid, status: "video_failed"); nil) if res.code != "201"
    @db["predictions"] << {"id" => data["id"], "session_id" => sid, "model" => "svd", "status" => "starting", "output" => nil, "created_at" => Time.now.to_i}
    save_db
    result = wait_for_prediction(data["id"], sid, "SVD")
    return nil unless result
    vid = result["output"].is_a?(Array) ? result["output"][0] : result["output"]
    update_session(sid, video_url: vid, status: "video_complete")
    vid
  end
  
  def execute_chain(chain_name, prompt)
    puts "\n" + "="*70
    puts "🎬 REPLIGEN #{VERSION} - CHAIN: #{chain_name.upcase}"
    puts "="*70
    
    chain = CHAINS[chain_name]
    chain = chain.call if chain.is_a?(Proc)
    
    puts "Chain: #{chain.join(' → ')}"
    puts "Estimated cost: $#{chain.map { |m| MODELS[m][:cost] }.sum.round(3)}"
    
    sid = @db["sessions"].length + 1
    @db["sessions"] << {
      "id" => sid, 
      "prompt" => prompt, 
      "chain" => chain_name.to_s,
      "models" => chain.join(","),
      "image_url" => nil, 
      "video_url" => nil, 
      "local_file" => nil, 
      "vps_path" => nil, 
      "status" => "created", 
      "cost" => nil, 
      "created_at" => Time.now.to_i, 
      "updated_at" => Time.now.to_i
    }
    save_db
    
    # Execute chain
    output = prompt
    chain.each_with_index do |model, i|
      puts "\n[Step #{i+1}/#{chain.size}] #{MODELS[model][:description]}"
      
      case model
      when :ra2
        output = generate_ra2_image(output, sid) or return
        update_session(sid, image_url: output)
      when :upscale
        output = upscale_image(output, sid) or return
      when :svd
        output = generate_video(output, sid) or return
        update_session(sid, video_url: output)
      end
    end
    
    # Download final output
    ext = chain.last == :svd ? "mp4" : "png"
    fn = "repligen_#{chain_name}_#{Time.now.strftime("%Y%m%d_%H%M%S")}.#{ext}"
    puts "\n📥 Downloading final output..."
    system("curl", "-s", "-o", fn, output)
    update_session(sid, local_file: fn)
    
    # Upload to VPS
    puts "\n📤 Uploading to VPS..."
    if system("scp", "-i", "G:\\priv\\passwd\\id_rsa", fn, "dev@185.52.176.18:/home/dev/")
      update_session(sid, vps_path: "/home/dev/#{fn}", status: "complete", cost: chain.map { |m| MODELS[m][:cost] }.sum)
      puts "✓ Uploaded to VPS"
    else
      update_session(sid, status: "upload_failed", cost: chain.map { |m| MODELS[m][:cost] }.sum)
    end
    
    total_cost = chain.map { |m| MODELS[m][:cost] }.sum
    puts "\n" + "="*70
    puts "✨ CHAIN COMPLETE!"
    puts "="*70
    puts "Session: #{sid}"
    puts "Chain: #{chain.join(' → ')}"
    puts "Local: #{fn}"
    puts "Cost: $#{total_cost.round(3)}"
    puts "="*70
  end
  
  def upscale_image(image_url, sid)
    puts "Upscaling to 4K..."
    # Placeholder - would call Real-ESRGAN here
    puts "⚠️  Upscale not yet implemented"
    image_url
  end
  
  def run(args)
    puts "❌ Set REPLICATE_API_TOKEN" and exit 1 unless @token
    if args.empty?
      puts "Available chains: #{CHAINS.keys.join(', ')}"
      print "Chain [motion]: "
      chain = gets.chomp
      chain = :motion if chain.empty?
      print "Prompt: "
      prompt = gets.chomp
      execute_chain(chain.to_sym, prompt)
    elsif args[0] == "chain"
      execute_chain(args[1].to_sym, args[2..-1].join(" "))
    else
      execute_chain(:motion, args.join(" "))
    end
  end
end

Repligen.new.run(ARGV) if __FILE__ == $0
