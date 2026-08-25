#!/usr/bin/env ruby
# frozen_string_literal: true

# frozen_string_literal: true

require "fileutils"
require "open3"
require "optparse"
require "shellwords"

ROOT = File.expand_path("..", __dir__)
DEFAULT_OUT = File.join(ROOT, "reports", "screenshots", "home.png")

options = {
  url: nil,
  out: DEFAULT_OUT,
  wait_ms: 1200,
  width: 1440,
  height: 1200,
}

OptionParser.new do |opts|
  opts.banner = "usage: web-screenshot URL [OUT.png] [--wait-ms N] [--width N] [--height N]"
  opts.on("--wait-ms N", Integer) { |value| options[:wait_ms] = value }
  opts.on("--width N", Integer) { |value| options[:width] = value }
  opts.on("--height N", Integer) { |value| options[:height] = value }
end.parse!

options[:url] = ARGV.shift
options[:out] = ARGV.shift || options[:out]
abort "FAIL web-screenshot: URL required" unless options[:url]

FileUtils.mkdir_p(File.dirname(options[:out]))

browser = %w[chromium chromium-browser google-chrome chrome].find do |cmd|
  system("command", "-v", cmd, out: File::NULL, err: File::NULL)
end

abort "FAIL web-screenshot: chromium/google-chrome not found" unless browser

args = [
  browser,
  "--headless=new",
  "--disable-gpu",
  "--no-sandbox",
  "--hide-scrollbars",
  "--window-size=#{options[:width]},#{options[:height]}",
  "--virtual-time-budget=#{options[:wait_ms]}",
  "--screenshot=#{options[:out]}",
  options[:url],
]

stdout, stderr, status = Open3.capture3(*args)
abort "FAIL web-screenshot: #{stderr.empty? ? stdout : stderr}" unless status.success? && File.exist?(options[:out]) && File.size(options[:out]).positive?

puts "OK screenshot: #{options[:out]}"
