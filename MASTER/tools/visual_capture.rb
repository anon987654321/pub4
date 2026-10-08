#!/usr/bin/env ruby
# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "optparse"
require "uri"
require "yaml"
require_relative "../gates/support/cdp_session"
require_relative "../gates/support/geometry_probe"

module MasterVisualCapture
  ROOT = File.expand_path("..", __dir__).freeze
  DEFAULT_OUTPUT = File.join(ROOT, ".master", "visual-capture")
  VIEWPORTS = {
    mobile: [390, 844],
    compact: [1024, 768],
    desktop: [1440, 900],
  }.freeze

  module_function

  def seed_for(key)
    Digest::SHA256.hexdigest(key.to_s)[0, 8].to_i(16)
  end

  def freeze_script(seed)
    <<~JS
      (() => {
        let state = #{seed} >>> 0;
        const random = () => (state = (state * 1664525 + 1013904223) >>> 0) / 2 ** 32;
        Math.random = random;
        const NativeDate = Date;
        class FixedDate extends NativeDate {
          static now() { return 1767225600000; }
          constructor(...args) { args.length === 0 ? super(FixedDate.now()) : super(...args); }
        }
        window.Date = FixedDate;
        window.__MASTER_VISUAL_CAPTURE__ = true;
      })();
    JS
  end

  def pause_motion(cdp)
    cdp.evaluate(<<~JS)
      (() => {
        document.querySelectorAll("style[data-master-visual-capture]").forEach((node) => node.remove());
        const style = document.createElement("style");
        style.dataset.masterVisualCapture = "true";
        style.textContent = `*, *::before, *::after {
          animation-duration: 0s !important;
          animation-delay: 0s !important;
          transition-duration: 0s !important;
          transition-delay: 0s !important;
          scroll-behavior: auto !important;
        }`;
        document.head.appendChild(style);
        document.getAnimations?.().forEach((animation) => animation.pause());
        return true;
      })()
    JS
  end

  def mask_volatile(cdp)
    selectors = YAML.safe_load_file(
      File.join(ROOT, "gates", "data", "geometry_surfaces.yml"),
      aliases: false,
    )["volatile_selectors"]
    return if Array(selectors).empty?

    rule = "#{Array(selectors).join(", ")} { visibility: hidden !important; }"
    html = "<style data-master-visual-mask>#{rule}</style>"
    cdp.evaluate("document.head.insertAdjacentHTML('beforeend', #{JSON.generate(html)})")
  end

  def parse_viewport(value)
    return VIEWPORTS.fetch(value.to_sym) if VIEWPORTS.key?(value.to_sym)

    width, height = value.to_s.split("x", 2).map(&:to_i)
    raise OptionParser::InvalidArgument, "viewport must be NAME or WIDTHxHEIGHT" unless width.positive? && height.positive?

    [width, height]
  end

  def options(argv)
    values = {
      width: nil,
      height: nil,
      output: DEFAULT_OUTPUT,
      app: "master",
      label: "capture",
      mask: true,
      freeze: true,
    }
    OptionParser.new do |opts|
      opts.banner = "Usage: ruby MASTER/tools/visual_capture.rb --url URL [options]"
      opts.on("--url URL", "Page URL") { |v| values[:url] = v }
      opts.on("--viewport NAME|WIDTHxHEIGHT", "Viewport") do |v|
        values[:width], values[:height] = parse_viewport(v)
      end
      opts.on("--app APP", "Application label") { |v| values[:app] = v }
      opts.on("--label LABEL", "Capture label") { |v| values[:label] = v }
      opts.on("--output DIR", "Output root") { |v| values[:output] = v }
      opts.on("--no-mask", "Do not mask volatile selectors") { values[:mask] = false }
      opts.on("--no-freeze", "Do not freeze random/date/animation state") { values[:freeze] = false }
      opts.on("-h", "--help") { puts opts; exit }
    end.parse!(argv)
    raise OptionParser::MissingArgument, "--url is required" if values[:url].to_s.empty?

    values[:width] ||= VIEWPORTS.fetch(:mobile).first
    values[:height] ||= VIEWPORTS.fetch(:mobile).last
    values
  end

  def surface(values)
    uri = URI.parse(values[:url])
    Deploy::GeometryProbe::Surface.new(
      app: values[:app],
      label: values[:label],
      host: nil,
      path: uri.path.to_s.empty? ? "/" : uri.path,
      viewport: "custom",
      port: uri.port,
      width: values[:width],
      height: values[:height],
    )
  end

  def run!(argv)
    values = options(argv)
    output = File.join(values[:output], values[:app], values[:label])
    FileUtils.mkdir_p(output)
    screenshot = File.join(output, "#{values[:width]}x#{values[:height]}.png")
    manifest = File.join(output, "#{values[:width]}x#{values[:height]}.json")
    key = "#{values[:app]}/#{values[:label]}@#{values[:width]}x#{values[:height]}"

    Deploy::CdpSession.open do |cdp|
      cdp.viewport(values[:width], values[:height], mobile: values[:width] < 500, scale: 2)
      cdp.headers(Deploy::GeometryProbe::PROBE_HEADERS)
      cdp.on_new_document(freeze_script(seed_for(key))) if values[:freeze]
      cdp.navigate(values[:url], settle: 0.2)
      pause_motion(cdp) if values[:freeze]
      mask_volatile(cdp) if values[:mask]

      current = surface(values)
      payload = Deploy::GeometryProbe.measure_current(cdp, current)
      raise "visual capture: geometry probe returned no payload" unless payload.is_a?(Hash)

      cdp.screenshot(screenshot, capture_beyond_viewport: false)
      record = {
        key:,
        url: values[:url],
        viewport: { width: values[:width], height: values[:height], scale: 2 },
        status: cdp.status,
        title: cdp.evaluate("document.title"),
        screenshot:,
        screenshot_sha256: Digest::SHA256.file(screenshot).hexdigest,
        console_errors: cdp.console_errors,
        geometry: payload,
      }
      File.write(manifest, JSON.pretty_generate(record) + "\n")
      puts JSON.pretty_generate(record.slice(:key, :status, :title, :screenshot, :screenshot_sha256))
    end
  rescue Deploy::CdpSession::Unavailable, Deploy::CdpSession::Error, SystemCallError => e
    warn "visual capture: INCONCLUSIVE — #{e.class}: #{e.message}"
    exit 3
  end
end

MasterVisualCapture.run!(ARGV) if $PROGRAM_NAME == __FILE__
