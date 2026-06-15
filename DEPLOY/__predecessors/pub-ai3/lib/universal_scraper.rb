# frozen_string_literal: true

require 'ferrum'
require 'nokogiri'
require 'fileutils'
require 'uri'
require 'digest'

# Universal Scraper with Ferrum for web content and screenshots
# Includes cognitive load awareness and depth-based analysis
class UniversalScraper
  attr_reader :browser, :config, :cognitive_monitor

  def initialize(config = {})
    @config = default_config.merge(config)
    @cognitive_monitor = nil
    @screenshot_dir = @config[:screenshot_dir]
    @max_depth = @config[:max_depth]
    @timeout = @config[:timeout]
    @user_agent = @config[:user_agent]

    # Ensure screenshot directory exists
    FileUtils.mkdir_p(@screenshot_dir)

    # Initialize browser with error handling
    initialize_browser
  end

  # Set cognitive monitor for load-aware processing
  def set_cognitive_monitor(monitor)
    @cognitive_monitor = monitor
  end

  # Main scraping method with cognitive awareness
  def scrape(url, options = {})
    # Check cognitive capacity
    if @cognitive_monitor&.cognitive_overload?
      puts '🧠 Cognitive overload detected, deferring scraping'
      return { error: 'Cognitive overload - scraping deferred' }
    end

    # Validate URL
    return { error: 'Invalid URL' } unless valid_url?(url)

    begin
      puts "🕷️ Scraping #{url}..."

      # Navigate to page
      @browser.go_to(url)
      wait_for_page_load

      # Take screenshot
      screenshot_path = take_screenshot(url)

      # Extract content
      content = extract_content

      # Analyze page structure
      analysis = analyze_page_structure

      # Extract links for depth-based scraping
      links = extract_links(url) if options[:extract_links]

      # Update cognitive load
      if @cognitive_monitor
        complexity = calculate_content_complexity(content)
        @cognitive_monitor.add_concept(url, complexity * 0.1)
      end

      result = {
        url: url,
        title: content[:title],
        content: content[:text],
        html: content[:html],
        screenshot: screenshot_path,
        analysis: analysis,
        links: links,
        timestamp: Time.now,
        success: true
      }

      puts "✅ Successfully scraped #{url}"
      result
    rescue StandardError => e
      puts "❌ Scraping failed for #{url}: #{e.message}"
      { url: url, error: e.message, success: false }
    end
  end

  # Scrape multiple URLs with cognitive load balancing
  def scrape_multiple(urls, options = {})
    results = []

    urls.each_with_index do |url, index|
      # Check cognitive state before each scrape
      if @cognitive_monitor&.cognitive_overload?
        puts "🧠 Cognitive overload detected, stopping batch scrape at #{index}/#{urls.size}"
        break
      end

      result = scrape(url, options)
      results << result

      # Brief pause between requests
      sleep(1) if options[:delay]

      # Progress update
      puts "📊 Progress: #{index + 1}/#{urls.size} URLs scraped"
    end

    results
  end

  # Deep scrape with configurable depth
  def deep_scrape(start_url, depth = nil, visited = Set.new)
    depth ||= @max_depth
    return [] if depth <= 0 || visited.include?(start_url)

    # Check cognitive capacity
    if @cognitive_monitor&.cognitive_overload?
      puts '🧠 Cognitive overload detected, stopping deep scrape'
      return []
    end

    visited.add(start_url)
    results = []

    # Scrape current page
    result = scrape(start_url, extract_links: true)
    results << result if result[:success]

    # Recursively scrape linked pages
    if result[:success] && result[:links]
      result[:links].take(5).each do |link| # Limit to 5 links per page
        next if visited.include?(link) || !same_domain?(start_url, link)

        deeper_results = deep_scrape(link, depth - 1, visited)
        results.concat(deeper_results)
      end
    end

    results
  end

  # Extract content from current page
  def extract_content
    title = @browser.evaluate('document.title') || ''

    # Extract main text content
    text_content = @browser.evaluate(<<~JS)
      // Remove script and style elements
      var scripts = document.querySelectorAll('script, style, nav, footer, aside');
      scripts.forEach(function(el) { el.remove(); });

      // Get main content areas
      var main = document.querySelector('main, article, .content, #content, .post, .article');
      if (main) {
        return main.innerText;
      }

      // Fallback to body content
      return document.body.innerText;
    JS

    # Get full HTML
    html = @browser.evaluate('document.documentElement.outerHTML')

    {
      title: title.strip,
      text: clean_text(text_content || ''),
      html: html
    }
  end

  # Take screenshot of current page
  def take_screenshot(url)
    # Generate filename based on URL
    filename = generate_screenshot_filename(url)
    filepath = File.join(@screenshot_dir, filename)

    # Take screenshot
    @browser.screenshot(path: filepath, format: 'png', quality: 80)

    puts "📸 Screenshot saved: #{filepath}"
    filepath
  rescue StandardError => e
    puts "❌ Screenshot failed: #{e.message}"
    nil
  end

  # Analyze page structure and content
  def analyze_page_structure
    structure = @browser.evaluate(<<~JS)
      function analyzeStructure() {
        var analysis = {
          headings: [],
          forms: [],
          images: [],
          links: 0,
          interactive_elements: 0,
          content_sections: 0
        };
      #{'  '}
        // Analyze headings
        var headings = document.querySelectorAll('h1, h2, h3, h4, h5, h6');
        headings.forEach(function(h) {
          analysis.headings.push({
            level: h.tagName,
            text: h.innerText.substring(0, 100)
          });
        });
      #{'  '}
        // Analyze forms
        var forms = document.querySelectorAll('form');
        forms.forEach(function(form) {
          var inputs = form.querySelectorAll('input, select, textarea').length;
          analysis.forms.push({
            action: form.action || '',
            method: form.method || 'GET',
            inputs: inputs
          });
        });
      #{'  '}
        // Count elements
        analysis.images = document.querySelectorAll('img').length;
        analysis.links = document.querySelectorAll('a[href]').length;
        analysis.interactive_elements = document.querySelectorAll('button, input, select, textarea').length;
        analysis.content_sections = document.querySelectorAll('article, section, .content, .post').length;
      #{'  '}
        return analysis;
      }

      analyzeStructure();
    JS

    structure || {}
  end

  # Extract links from current page
  def extract_links(base_url)
    links = @browser.evaluate(<<~JS)
      var links = [];
      var anchors = document.querySelectorAll('a[href]');

      anchors.forEach(function(a) {
        var href = a.href;
        if (href && !href.startsWith('javascript:') && !href.startsWith('mailto:')) {
          links.push(href);
        }
      });

      return links;
    JS

    # Convert relative URLs to absolute
    (links || []).map do |link|
      resolve_url(base_url, link)
    end.compact.uniq
  end

  # Close browser
  def close
    @browser&.quit
    puts '🔌 Browser closed'
  end

  private

  # Default configuration
  def default_config
    {
      screenshot_dir: 'data/screenshots',
      max_depth: 2,
      timeout: 30,
      user_agent: 'AI3-UniversalScraper/1.0',
      window_size: [1920, 1080],
      headless: true
    }
  end

  # Initialize Ferrum browser
  def initialize_browser
    options = {
      headless: @config[:headless],
      timeout: @config[:timeout],
      window_size: @config[:window_size],
      browser_options: {
        'user-agent' => @user_agent,
        'disable-gpu' => nil,
        'no-sandbox' => nil,
        'disable-dev-shm-usage' => nil
      }
    }

    @browser = Ferrum::Browser.new(**options)
    puts '🌐 Browser initialized'
  rescue StandardError => e
    puts "❌ Failed to initialize browser: #{e.message}"
    puts '💡 Make sure Chrome/Chromium is installed'
    raise
  end

  # Wait for page to load
  def wait_for_page_load(timeout = 10)
    @browser.evaluate_async(<<~JS, timeout)
      if (document.readyState === 'complete') {
        arguments[0]();
      } else {
        window.addEventListener('load', arguments[0]);
      }
    JS
  rescue Ferrum::TimeoutError
    puts '⚠️ Page load timeout'
  end

  # Validate URL format
  def valid_url?(url)
    uri = URI.parse(url)
    uri.is_a?(URI::HTTP) || uri.is_a?(URI::HTTPS)
  rescue URI::InvalidURIError
    false
  end

  # Generate screenshot filename
  def generate_screenshot_filename(url)
    # Create a safe filename from URL
    safe_name = url.gsub(/[^a-zA-Z0-9]/, '_')
    hash = Digest::SHA256.hexdigest(url)[0..8]
    timestamp = Time.now.strftime('%Y%m%d_%H%M%S')

    "#{timestamp}_#{hash}_#{safe_name[0..50]}.png"
  end

  # Clean extracted text
  def clean_text(text)
    # Remove extra whitespace and normalize
    text.gsub(/\s+/, ' ')
        .gsub(/\n\s*\n/, "\n")
        .strip
  end

  # Calculate content complexity for cognitive load
  def calculate_content_complexity(content)
    return 1.0 unless content.is_a?(Hash)

    complexity = 0

    # Text length factor
    text_length = content[:text]&.length || 0
    complexity += (text_length / 1000.0).clamp(0, 3)

    # HTML complexity
    html = content[:html] || ''
    complexity += (html.scan(/<[^>]+>/).size / 100.0).clamp(0, 2)

    # Title complexity
    title = content[:title] || ''
    complexity += (title.split.size / 10.0).clamp(0, 1)

    complexity.clamp(1.0, 5.0)
  end

  # Resolve relative URLs
  def resolve_url(base_url, link)
    URI.join(base_url, link).to_s
  rescue URI::InvalidURIError
    nil
  end

  # Check if URLs are from same domain
  def same_domain?(url1, url2)
    URI.parse(url1).host == URI.parse(url2).host
  rescue URI::InvalidURIError
    false
  end
end
