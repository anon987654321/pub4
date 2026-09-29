#!/usr/bin/env ruby
# frozen_string_literal: true

require "net/http"
require "optparse"
require "set"
require "uri"

options = { url: "https://brgen.no/", limit: 250, timeout: 10 }
OptionParser.new do |opts|
  opts.on("--url URL") { |v| options[:url] = v }
  opts.on("--limit N", Integer) { |v| options[:limit] = v }
  opts.on("--timeout SEC", Integer) { |v| options[:timeout] = v }
end.parse!

origin = URI(options[:url])
queue = [origin]
seen = Set.new
findings = []

while (uri = queue.shift) && seen.length < options[:limit]
  next unless uri.host == origin.host
  key = uri.to_s
  next if seen.include?(key)

  seen << key
  response = begin
    Net::HTTP.start(uri.hostname, uri.port, use_ssl: uri.scheme == "https",
                    open_timeout: options[:timeout], read_timeout: options[:timeout]) do |http|
      http.get(uri.request_uri)
    end
  rescue StandardError => error
    findings << { url: uri.to_s, error: "#{error.class}: #{error.message}" }
    next
  end

  findings << { url: uri.to_s, status: response.code.to_i } unless response.code.to_i.between?(200, 399)
  next unless response["content-type"].to_s.include?("text/html")

  body = response.body.to_s
  body.scan(/<a\b[^>]*href\s*=\s*["']([^"']+)["']/i).flatten.each do |href|
    if href.strip == "#"
      findings << { url: uri.to_s, rule: "href_hash" }
      next
    end
    next if href.match?(/\A(?:mailto|tel|javascript):/i)

    child = URI.join(uri.to_s, href).tap { |u| u.fragment = nil } rescue nil
    queue << child if child && child.host == origin.host
  end
end

puts "dead-link-census: pages=#{seen.length} findings=#{findings.length}"
findings.each { |finding| warn finding.inspect }
exit 1 unless findings.empty?
