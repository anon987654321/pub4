#!/usr/bin/env ruby
# frozen_string_literal: true

require "fileutils"
require "open3"
require "optparse"
require "shellwords"
require_relative "../lib/trace/dmesg"

MASTER_DIR = File.expand_path("..", __dir__)
DEFAULT_OUT = File.join(MASTER_DIR, "reports", "screenshots", "home.png")

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
unless options[:url]
  Master::Trace::Dmesg.status("screenshot0", "URL required", io: $stderr)
  exit 64
end

FileUtils.mkdir_p(File.dirname(options[:out]))

browser = %w[chromium chromium-browser google-chrome chrome].find do |cmd|
  system("command", "-v", cmd, out: File::NULL, err: File::NULL)
end

unless browser
  Master::Trace::Dmesg.status("screenshot0", "chromium or google-chrome not found", io: $stderr)
  exit 1
end

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
unless status.success? && File.exist?(options[:out]) && File.size(options[:out]).positive?
  Master::Trace::Dmesg::Report.print("screenshot0", stderr.empty? ? stdout : stderr, io: $stderr)
  Master::Trace::Dmesg.status("screenshot0", "failed", io: $stderr)
  exit(status.exitstatus || 1)
end

Master::Trace::Dmesg.status("screenshot0", "screenshot #{options[:out]}")
