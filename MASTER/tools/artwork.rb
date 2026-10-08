#!/usr/bin/env ruby
# frozen_string_literal: true

require "cgi"
require "digest"
require "fileutils"
require "json"
require "optparse"
require "uri"
require_relative "../lib/trace/dmesg"

class HouseArtwork
  CHROME_PATHS = [
    ENV["CHROME_PATH"],
    "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
    "/Applications/Chromium.app/Contents/MacOS/Chromium",
    "/usr/local/bin/chromium",
    "/usr/local/bin/chrome",
  ].compact.freeze

  def self.run!(argv)
    options = {
      text: "Bergen",
      output: "artwork.png",
      width: 1200,
      height: 630,
      seed: nil,
      title: "House artwork",
    }

    OptionParser.new do |opts|
      opts.banner = "usage: artwork.rb --output PATH [options]"
      opts.on("--output PATH") { |v| options[:output] = File.expand_path(v) }
      opts.on("--text TEXT") { |v| options[:text] = v }
      opts.on("--title TEXT") { |v| options[:title] = v }
      opts.on("--width PX", Integer) { |v| options[:width] = v }
      opts.on("--height PX", Integer) { |v| options[:height] = v }
      opts.on("--seed SEED") { |v| options[:seed] = v }
    end.parse!(argv)

    new(options).run!
  end

  def initialize(options)
    @options = options
    @seed = @options[:seed].to_s.empty? ? Digest::SHA256.hexdigest(@options[:text].to_s)[0, 12] : @options[:seed].to_s
  end

  def run!
    require "ferrum"
    chrome = CHROME_PATHS.find { |path| File.executable?(path) }
    unless chrome
      Master::Trace::Dmesg.status("artwork0", "no Chrome executable", io: $stderr)
      exit 1
    end

    FileUtils.mkdir_p(File.dirname(@options[:output]))
    html = File.join(Dir.tmpdir, "pub4-artwork-#{Process.pid}-#{@seed}.html")
    File.write(html, document)

    browser = Ferrum::Browser.new(
      browser_path: chrome,
      headless: "new",
      timeout: 60,
      browser_options: {
        "no-sandbox" => nil,
        "disable-dev-shm-usage" => nil,
        "disable-gpu" => nil,
      },
    )

    browser.go_to("file://#{html}")
    browser.resize(width: @options[:width], height: @options[:height])
    browser.screenshot(path: @options[:output], full: false)
    # JSON remains an explicit machine payload.
    puts JSON.generate(
      renderer: "g1",
      seed: @seed,
      width: @options[:width],
      height: @options[:height],
      output: @options[:output],
    )
  ensure
    browser&.quit
    FileUtils.rm_f(html) if html
  end

  private

  def document
    <<~HTML
      <!doctype html>
      <html lang="nb">
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=#{@options[:width]},initial-scale=1">
          <title>#{escape(@options[:title])}</title>
          <style>
            :root { color-scheme: light; }
            html, body { margin: 0; inline-size: 100%; block-size: 100%; overflow: hidden; }
            body {
              background: #f7f4ec;
              color: #171717;
              font-family: Georgia, "Times New Roman", serif;
            }
            .frame {
              position: relative;
              inline-size: 100%;
              block-size: 100%;
              overflow: hidden;
            }
            .grid {
              position: absolute;
              inset: 0;
              opacity: .16;
              background-image:
                linear-gradient(#171717 1px, transparent 1px),
                linear-gradient(90deg, #171717 1px, transparent 1px);
              background-size: 48px 48px;
            }
            .copy {
              position: absolute;
              inset-inline: 8%;
              inset-block-end: 9%;
              max-inline-size: 74%;
              z-index: 2;
            }
            .kicker {
              font: 700 14px/1.1 system-ui, sans-serif;
              letter-spacing: .12em;
              text-transform: uppercase;
            }
            h1 {
              margin: 12px 0 0;
              font-size: clamp(44px, 8vw, 92px);
              line-height: .92;
              letter-spacing: -.035em;
            }
            .mark { position: absolute; inset-block-start: 8%; inset-inline-end: 8%; z-index: 2; }
            .mark circle { fill: #171717; }
            .mark path { stroke: #f7f4ec; stroke-width: 2; fill: none; }
          </style>
        </head>
        <body>
          <div class="frame">
            <div class="grid"></div>
            <svg viewBox="0 0 1200 630" aria-hidden="true" width="100%" height="100%" preserveAspectRatio="none">
              #{art_svg}
            </svg>
            <div class="mark">
              <svg width="88" height="88" viewBox="0 0 88 88">
                <circle cx="44" cy="44" r="43"></circle>
                <path d="M18 44h52M44 18v52M28 28l32 32M60 28L28 60"></path>
              </svg>
            </div>
            <div class="copy">
              <div class="kicker">#{escape(@options[:title])}</div>
              <h1>#{escape(@options[:text])}</h1>
            </div>
          </div>
        </body>
      </html>
    HTML
  end

  def art_svg
    state = @seed.each_byte.sum
    circles = 18.times.map do |index|
      x = 70 + ((state * (index + 3) * 17) % 1060)
      y = 70 + ((state * (index + 5) * 11) % 490)
      r = 10 + ((state + index * 7) % 42)
      opacity = (0.16 + ((index % 5) * 0.04)).round(2)
      "<circle cx=\"#{x}\" cy=\"#{y}\" r=\"#{r}\" fill=\"#171717\" opacity=\"#{opacity}\"></circle>"
    end
    paths = 7.times.map do |index|
      y = 80 + index * 74
      "<path d=\"M0 #{y} C 180 #{y - 65}, 340 #{y + 65}, 560 #{y} S 940 #{y - 65}, 1200 #{y}\" stroke=\"#171717\" stroke-width=\"2\" opacity=\"0.28\" fill=\"none\"></path>"
    end
    (circles + paths).join
  end

  def escape(value)
    CGI.escapeHTML(value.to_s)
  end
end

HouseArtwork.run!(ARGV)
