#!/usr/bin/env ruby
require "net/http"
require "json"

TOKEN = ENV["REPLICATE_API_TOKEN"] || ARGV[0]

unless TOKEN
  puts "Usage: #{$0} <api_token>"
  exit 1
end

uri = URI("https://api.replicate.com/v1/account")
req = Net::HTTP::Get.new(uri)
req["Authorization"] = "Token #{TOKEN}"

res = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) { |http| http.request(req) }

puts "=== REPLICATE API TEST ==="
if res.code == "200"
  data = JSON.parse(res.body)
  puts "✅ API Key Valid!"
  puts "   Account: #{data["username"]}"
  puts "   Type: #{data["type"]}"
  puts ""
  puts "✓ Ready for image/video generation"
else
  puts "❌ API Error: #{res.code}"
  puts res.body
end
