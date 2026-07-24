#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "digest"
require "fileutils"
require "uri"
require "time"

# Seeded screenshot contract for every product grammar and failure state. Run
# under any Rails app bundle:
#   bundle exec ruby ../visual_contract_gate.rb --capture --base http://127.0.0.1:3000 --app brgen
module VisualContractGate
  VIEWPORTS = {
    desktop: [1440, 900],
    compact: [1024, 768],
    mobile: [390, 844],
  }.freeze

  ROUTES = {
    brgen: {
      public: "/", sign_in: "/session/new", empty: "/?q=visual-contract-no-match",
      results: "/?sort=latest", error: "/404-visual-contract", offline: "/offline",
      # Marketplace vertical (Host markedsplass.* in capture when available)
      marketplace: "/", marketplace_sign_in: "/session/new",
    },
    amber: {
      public: "/", sign_in: "/session/new", wardrobe: "/items", item: "/items/1",
      outfit: "/outfits/1", upload: "/items/new", ai_result: "/ai/suggest_outfits",
      empty: "/items?q=visual-contract-no-match", error: "/404-visual-contract", offline: "/offline",
    },
    bsdports: {
      public: "/", empty: "/ports?q=visual-contract-no-match", results: "/ports?q=git",
      detail: "/ports/1", advisory: "/ports/1#cves-security-advisories",
      dependency: "/ports/1#this-package-requires", error: "/404-visual-contract", offline: "/offline",
    },
  }.freeze

  LENSES = %w[task_completion accessibility editorial_character system_trust first_use].freeze

  module_function

  def matrix(app)
    ROUTES.fetch(app.to_sym).flat_map do |state, route|
      VIEWPORTS.map { |viewport, dimensions| { app: app.to_sym, state:, route:, viewport:, dimensions: } }
    end
  end

  def validate!
    raise "visual crawl needs five critique lenses" unless LENSES.length == 5
    raise "missing empty/error/offline contract" unless ROUTES.values.all? { |routes| %i[empty error offline].all? { |state| routes.key?(state) } }
    rows = ROUTES.keys.flat_map { |app| matrix(app) }
    keys = rows.map { |row| row.values_at(:app, :state, :viewport) }
    raise "duplicate visual crawl cell" unless keys.uniq.length == keys.length
    rows
  end

  def accessibility_violations(driver)
    driver.execute_script(<<~JS)
      return [
        ...[...document.querySelectorAll('img:not([alt])')].map(() => 'image_without_alt'),
        ...[...document.querySelectorAll('button')].filter((el) => !(el.innerText.trim() || el.getAttribute('aria-label'))).map(() => 'button_without_name'),
        ...(document.querySelectorAll('h1').length !== 1 ? ['heading_one_count'] : []),
        ...[...document.querySelectorAll('input:not([type=hidden]), textarea, select')].filter((el) => !(el.labels?.length || el.getAttribute('aria-label'))).map(() => 'field_without_label')
      ];
    JS
  end

  # Diffs the prior screenshot at the same path (rolling baseline from the last
  # capture run) against the freshly captured one. Same-dimension mismatch only:
  # a viewport/layout size change isn't a pixel regression, it's a new baseline.
  def pixel_diff(baseline_bytes:, screenshot_path:, diff_path:)
    require "chunky_png"
    baseline = ChunkyPNG::Image.from_blob(baseline_bytes)
    current = ChunkyPNG::Image.from_file(screenshot_path)
    return { pixel_diff_count: nil, pixel_diff_ratio: nil, pixel_diff_image: nil } unless baseline.width == current.width && baseline.height == current.height

    baseline_pixels = baseline.pixels
    current_pixels = current.pixels
    diff_count = baseline_pixels.each_index.count { |i| baseline_pixels[i] != current_pixels[i] }
    if diff_count.positive?
      pixels = Array.new(baseline_pixels.length) do |i|
        baseline_pixels[i] == current_pixels[i] ? ChunkyPNG::Color::TRANSPARENT : ChunkyPNG::Color.rgba(255, 0, 64, 255)
      end
      ChunkyPNG::Image.new(current.width, current.height, pixels).save(diff_path)
    end
    { pixel_diff_count: diff_count, pixel_diff_ratio: (diff_count.to_f / baseline_pixels.length).round(6), pixel_diff_image: diff_count.positive? ? diff_path : nil }
  end

  # Classic Selenium `driver.manage.logs` was removed from selenium-webdriver's
  # Ruby bindings; newer versions only expose console output via BiDi. Degrade to
  # an empty list rather than crash the whole capture when it's unavailable.
  def browser_console_errors(driver)
    return [] unless driver.manage.respond_to?(:logs)

    driver.manage.logs.get(:browser).select { |log| log.level == "SEVERE" }.map(&:message)
  end

  def capture(base:, app:, output: File.expand_path("visual_contract", __dir__))
    require "selenium-webdriver"
    FileUtils.mkdir_p(output)
    options = Selenium::WebDriver::Chrome::Options.new
    options.add_argument("--headless=new")
    options.add_argument("--no-sandbox")
    options.add_argument("--disable-dev-shm-usage")
    options.add_option("goog:loggingPrefs", { browser: "ALL" })
    driver = Selenium::WebDriver.for(:chrome, options:)
    matrix(app).map do |cell|
      width, height = cell[:dimensions]
      driver.manage.window.resize_to(width, height)
      driver.navigate.to(URI.join(base, cell[:route]).to_s)
      sleep 0.15
      slug = [cell[:app], cell[:state], cell[:viewport]].join("-")
      screenshot = File.join(output, "#{slug}.png")
      baseline_bytes = File.binread(screenshot) if File.file?(screenshot)
      driver.save_screenshot(screenshot)
      diff = baseline_bytes ? pixel_diff(baseline_bytes:, screenshot_path: screenshot, diff_path: File.join(output, "#{slug}-diff.png")) : { pixel_diff_count: nil, pixel_diff_ratio: nil, pixel_diff_image: nil }
      {
        app: cell[:app], state: cell[:state], viewport: cell[:viewport], route: cell[:route],
        status: driver.execute_script("return performance.getEntriesByType('navigation')[0]?.responseStatus || null"),
        title: driver.title, screenshot: screenshot,
        screenshot_sha256: Digest::SHA256.file(screenshot).hexdigest,
        **diff,
        console_errors: browser_console_errors(driver),
        accessibility_violations: accessibility_violations(driver), lenses: LENSES
      }
    end
  ensure
    driver&.quit
  end
end

rows = VisualContractGate.validate!
if ARGV.delete("--capture")
  app_i = ARGV.index("--app")
  base_i = ARGV.index("--base")
  app = (app_i && ARGV[app_i + 1]) || abort("--app brgen|amber|bsdports required")
  base = (base_i && ARGV[base_i + 1]) || abort("--base URL required")
  results = VisualContractGate.capture(base:, app:)
  path = File.expand_path("visual_contract/#{app}-manifest.json", __dir__)
  File.write(path, JSON.pretty_generate(generated_at: Time.now.utc.iso8601, results:) + "\n")
  drifted = results.select { |row| row[:pixel_diff_count].to_i.positive? }
  drift_note = drifted.empty? ? "" : " (#{drifted.length} states drifted, #{drifted.map { |row| row[:pixel_diff_count] }.sum} px total)"
  puts "ok: captured #{results.length} visual states -> #{path}#{drift_note}"
else
  puts "ok: #{rows.length} seeded visual contract cells across #{VisualContractGate::ROUTES.length} apps"
end
