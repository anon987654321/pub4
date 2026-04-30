# lib/tools/universal_scraper.rb
#
# UniversalScraper: Fetches and refines web content using Ferrum and Nokogiri.
# Captures page source and optionally a screenshot, then refines the content.

require "nokogiri"
require "open-uri"
require "ferrum"
require "logger"
require "digest"

class UniversalScraper
  USER_AGENTS = [
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/91.0.4472.124 Safari/537.36",
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 Safari/605.1.15"
  ].freeze

  def initialize(options = {})
    @logger = Logger.new(STDOUT)
    @logger.level = Logger::INFO
    @options = {
      timeout: 120,
      process_timeout: 240,
      browser_path: nil,   # Use default if not specified
      xvfb: true,
      unveil: true,
      user_agent: USER_AGENTS.sample,
      take_screenshots: true
    }.merge(options)
  end

  def scrape(url)
    @logger.info("Scraping URL: #{url}")
    browser = initialize_browser
    browser.goto(url)
    sleep 2  # Allow dynamic content to load
    page_source = browser.body
    screenshot = nil
    if @options[:take_screenshots]
      screenshot = take_screenshot(browser, url)
      @logger.info("Screenshot captured: #{screenshot}")
    end
    browser.quit
    refined_content = refine_content(page_source)
    @logger.info("Scraping completed for #{url}")
    refined_content
  rescue StandardError => e
    @logger.error("Error scraping #{url}: #{e.message}")
    ""
  end

  # Execute method for tool manager integration.
  def execute(url, *args)
    scrape(url)
  end

  private

  def initialize_browser
    browser_options = {
      headless: true,
      timeout: @options[:timeout],
      process_timeout: @options[:process_timeout],
      user_agent: @options[:user_agent]
    }
    browser_options[:browser_path] = @options[:browser_path] if @options[:browser_path]
    Ferrum::Browser.new(browser_options)
  rescue StandardError => e
    @logger.error("Failed to initialize browser: #{e.message}")
    raise
  end

  def refine_content(html)
    doc = Nokogiri::HTML(html)
    selectors = "article, section, div, p, h1, h2, h3"
    elements = doc.css(selectors)
    if elements.empty?
      @logger.warn("No main content found with selectors; returning full HTML.")
      return html
    end
    elements.map { |el| el.text.strip }.reject(&:empty?).join("\n\n")
  end

  def take_screenshot(browser, url)
    filename = sanitize_filename(url) + ".png"
    browser.screenshot(path: filename)
    filename
  rescue StandardError => e
    @logger.error("Failed to capture screenshot: #{e.message}")
    nil
  end

  def sanitize_filename(url)
    url.gsub(%r{https?://}, "").gsub(/[^0-9A-Za-z.\-]/, "_")[0...255]
  end
end

