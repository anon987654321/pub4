#!/usr/bin/env ruby
# frozen_string_literal: true
# Ferrum Demo - Execute HTML/JS and Screenshot
# Requires: gem install ferrum

require 'ferrum'
require 'fileutils'

class FerrumDemo
  def initialize
    @browser = Ferrum::Browser.new(
      headless: true,
      window_size: [1920, 1080],
      timeout: 30,
      browser_options: {
        'no-sandbox': nil,
        'disable-gpu': nil,
        'disable-dev-shm-usage': nil
      }
    )
  end

  # Execute HTML string and screenshot
  def execute_html(html_content, output_path = 'screenshot.png')
    # Create data URL from HTML
    html_base64 = Base64.strict_encode64(html_content)
    data_url = "data:text/html;base64,#{html_base64}"
    
    @browser.goto(data_url)
    @browser.screenshot(path: output_path)
    
    puts "✓ Screenshot saved: #{output_path}"
    output_path
  end

  # Execute HTML file and screenshot
  def execute_html_file(file_path, output_path = nil)
    output_path ||= file_path.sub(/\.html?$/, '_screenshot.png')
    
    # Convert to file:// URL
    abs_path = File.absolute_path(file_path)
    file_url = "file://#{abs_path}"
    
    @browser.goto(file_url)
    @browser.screenshot(path: output_path)
    
    puts "✓ Screenshot saved: #{output_path}"
    output_path
  end

  # Execute URL and screenshot
  def execute_url(url, output_path = 'url_screenshot.png')
    @browser.goto(url)
    @browser.screenshot(path: output_path)
    
    puts "✓ Screenshot saved: #{output_path}"
    output_path
  end

  # Execute JS and return result
  def execute_js(js_code)
    result = @browser.evaluate(js_code)
    puts "JS Result: #{result.inspect}"
    result
  end

  # Full page screenshot (scrolling)
  def full_page_screenshot(url, output_path = 'fullpage.png')
    @browser.goto(url)
    
    # Get full page dimensions
    height = @browser.evaluate('document.documentElement.scrollHeight')
    @browser.resize(width: 1920, height: height)
    
    @browser.screenshot(path: output_path, full: true)
    
    puts "✓ Full page screenshot saved: #{output_path}"
    output_path
  end

  # Interactive demo
  def demo_interactive
    html = <<~HTML
      <!DOCTYPE html>
      <html>
      <head>
        <style>
          body {
            font-family: 'Segoe UI', Tahoma, sans-serif;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            display: flex;
            justify-content: center;
            align-items: center;
            height: 100vh;
            margin: 0;
          }
          .card {
            background: white;
            padding: 60px;
            border-radius: 20px;
            box-shadow: 0 20px 60px rgba(0,0,0,0.3);
            text-align: center;
            animation: fadeIn 1s ease-in;
          }
          @keyframes fadeIn {
            from { opacity: 0; transform: translateY(-20px); }
            to { opacity: 1; transform: translateY(0); }
          }
          h1 {
            color: #667eea;
            margin: 0 0 20px 0;
            font-size: 48px;
          }
          .time {
            font-size: 72px;
            font-weight: bold;
            color: #764ba2;
            font-family: 'Courier New', monospace;
          }
          .date {
            color: #666;
            font-size: 24px;
            margin-top: 20px;
          }
        </style>
      </head>
      <body>
        <div class="card">
          <h1>Ferrum Demo</h1>
          <div class="time" id="time"></div>
          <div class="date" id="date"></div>
        </div>
        <script>
          function updateTime() {
            const now = new Date();
            document.getElementById('time').textContent = 
              now.toLocaleTimeString('en-US', { hour12: false });
            document.getElementById('date').textContent = 
              now.toLocaleDateString('en-US', { 
                weekday: 'long', 
                year: 'numeric', 
                month: 'long', 
                day: 'numeric' 
              });
          }
          updateTime();
          setInterval(updateTime, 1000);
        </script>
      </body>
      </html>
    HTML

    execute_html(html, 'ferrum_demo.png')
  end

  # Chart/visualization demo
  def demo_chart
    html = <<~HTML
      <!DOCTYPE html>
      <html>
      <head>
        <script src="https://cdn.jsdelivr.net/npm/chart.js"></script>
        <style>
          body {
            font-family: Arial, sans-serif;
            padding: 40px;
            background: #f5f5f5;
          }
          canvas {
            background: white;
            border-radius: 10px;
            box-shadow: 0 4px 6px rgba(0,0,0,0.1);
          }
        </style>
      </head>
      <body>
        <canvas id="chart" width="800" height="400"></canvas>
        <script>
          const ctx = document.getElementById('chart').getContext('2d');
          new Chart(ctx, {
            type: 'bar',
            data: {
              labels: ['OpenBSD', 'FreeBSD', 'NetBSD', 'DragonflyBSD'],
              datasets: [{
                label: 'Awesomeness Level',
                data: [95, 90, 85, 88],
                backgroundColor: [
                  'rgba(255, 206, 86, 0.8)',
                  'rgba(75, 192, 192, 0.8)',
                  'rgba(153, 102, 255, 0.8)',
                  'rgba(255, 99, 132, 0.8)'
                ]
              }]
            },
            options: {
              scales: { y: { beginAtZero: true, max: 100 } },
              plugins: {
                title: {
                  display: true,
                  text: 'BSD Operating Systems Comparison',
                  font: { size: 20 }
                }
              }
            }
          });
        </script>
      </body>
      </html>
    HTML

    # Wait for Chart.js to load and render
    @browser.goto("data:text/html;base64,#{Base64.strict_encode64(html)}")
    sleep 2  # Give Chart.js time to render
    @browser.screenshot(path: 'ferrum_chart.png')
    
    puts "✓ Chart screenshot saved: ferrum_chart.png"
  end

  # Get page info
  def page_info
    {
      title: @browser.title,
      url: @browser.url,
      body_text: @browser.body,
      cookies: @browser.cookies.all
    }
  end

  def close
    @browser.quit
  end
end

# Main execution
if __FILE__ == $0
  require 'base64'
  
  puts "Ferrum Demo - Headless Chrome for Ruby"
  puts "=" * 50
  
  begin
    demo = FerrumDemo.new
    
    puts "\n1. Creating interactive demo..."
    demo.demo_interactive
    
    puts "\n2. Creating chart visualization..."
    demo.demo_chart
    
    puts "\n3. Testing JavaScript execution..."
    result = demo.execute_js('2 + 2')
    puts "   2 + 2 = #{result}"
    
    result = demo.execute_js('navigator.userAgent')
    puts "   User Agent: #{result[0..60]}..."
    
    puts "\n✓ All demos complete!"
    puts "\nGenerated files:"
    puts "  - ferrum_demo.png (interactive clock)"
    puts "  - ferrum_chart.png (Chart.js visualization)"
    
  rescue LoadError
    puts "\n✗ ERROR: Ferrum gem not installed"
    puts "\nInstall with: gem install ferrum"
    puts "\nNote: Requires Chrome/Chromium browser installed"
    puts "  - macOS: brew install chromium"
    puts "  - Ubuntu: sudo apt install chromium-browser"
    puts "  - OpenBSD: pkg_add chromium"
  ensure
    demo&.close
  end
end
