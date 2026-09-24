# frozen_string_literal: true

# Requests every resolved URL as a guest against the local app and sorts
# it: page (200 HTML), auth (redirect to sign-in), redirect (elsewhere),
# error (4xx/5xx). Writes probed_<app>.jsonl beside the input.
require "json"
require "net/http"

PORTS = { "amber" => 61352, "bsdports" => 47312, "brgen" => 38182 }.freeze
SIGN_IN = %r{/(session|sessions|sign_in|login|users/sign_in|auth)\b}

app, input = ARGV
out = File.join(File.dirname(input), "probed_#{app}.jsonl")
rows = File.readlines(input).select { |l| l.start_with?("{") }.map { |l| JSON.parse(l) }
rows = rows.select { |r| r["missing"].empty? }.uniq { |r| [r["url"], r["subdomain"]] }

File.open(out, "w") do |file|
  rows.each do |row|
    host = if app == "brgen"
             subs = Array(row["subdomain"])
             sub = subs.include?("markedsplass") ? "markedsplass" : subs.first
             sub ? "#{sub}.brgen.no" : "brgen.no"
           else
             "localhost"
           end
    http = Net::HTTP.new("127.0.0.1", PORTS.fetch(app))
    http.open_timeout = 5
    http.read_timeout = 30
    row["url"] = row["url"].squeeze("/")
    response = http.get(row["url"], "Host" => host, "Accept" => "text/html")
    location = response["location"].to_s
    kind = case response.code.to_i
           when 200 then response["content-type"].to_s.include?("html") ? "page" : "non_html"
           when 300..399 then location.match?(SIGN_IN) ? "auth" : "redirect"
           else "error"
           end
    file.puts JSON.generate(row.merge("host" => host, "status" => response.code.to_i, "kind" => kind, "location" => location))
  rescue StandardError => e
    file.puts JSON.generate(row.merge("host" => host, "status" => 0, "kind" => "error", "location" => "#{e.class}: #{e.message}"[0, 120]))
  end
end
tally = File.readlines(out).map { |l| JSON.parse(l)["kind"] }.tally
puts "#{app}: #{tally.inspect}"
