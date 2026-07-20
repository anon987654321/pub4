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
      driver.save_screenshot(screenshot)
      {
        app: cell[:app], state: cell[:state], viewport: cell[:viewport], route: cell[:route],
        status: driver.execute_script("return performance.getEntriesByType('navigation')[0]?.responseStatus || null"),
        title: driver.title, screenshot: screenshot,
        screenshot_sha256: Digest::SHA256.file(screenshot).hexdigest,
        console_errors: driver.manage.logs.get(:browser).select { |log| log.level == "SEVERE" }.map(&:message),
        accessibility_violations: accessibility_violations(driver), lenses: LENSES
      }
    end
  ensure
    driver&.quit
  end
end

rows = VisualContractGate.validate!
if ARGV.delete("--capture")
  app = (ARGV[ARGV.index("--app") + 1] rescue nil) || abort("--app brgen|amber|bsdports required")
  base = (ARGV[ARGV.index("--base") + 1] rescue nil) || abort("--base URL required")
  results = VisualContractGate.capture(base:, app:)
  path = File.expand_path("visual_contract/#{app}-manifest.json", __dir__)
  File.write(path, JSON.pretty_generate(generated_at: Time.now.utc.iso8601, results:) + "\n")
  puts "ok: captured #{results.length} visual states -> #{path}"
else
  puts "ok: #{rows.length} seeded visual contract cells across #{VisualContractGate::ROUTES.length} apps"
end
