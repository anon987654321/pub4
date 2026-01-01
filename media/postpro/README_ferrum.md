# Ferrum - Headless Chrome for Ruby

## What is Ferrum?

**Ferrum** is a high-level API to control Chrome/Chromium via the Chrome DevTools Protocol (CDP). Unlike Selenium, it talks directly to Chrome without a middleman.

## Use Cases

1. **Web Scraping**: Extract data from JavaScript-heavy sites
2. **Testing**: E2E testing of web applications  
3. **Screenshots**: Capture web pages, charts, dashboards
4. **PDF Generation**: Convert HTML to PDF
5. **Automation**: Automate browser tasks

## Installation

```bash
# Install gem
gem install ferrum

# Install Chrome/Chromium
# macOS
brew install chromium

# Ubuntu/Debian
sudo apt install chromium-browser

# OpenBSD
doas pkg_add chromium
```

## Basic Usage

```ruby
require 'ferrum'

# Create browser instance
browser = Ferrum::Browser.new(headless: true)

# Navigate to URL
browser.goto('https://example.com')

# Take screenshot
browser.screenshot(path: 'example.png')

# Execute JavaScript
result = browser.evaluate('document.title')
puts result  # => "Example Domain"

# Get page content
html = browser.body
puts html

# Close browser
browser.quit
```

## Advanced Features

### Execute Custom HTML/JS

```ruby
html = <<~HTML
  <!DOCTYPE html>
  <html>
  <head>
    <style>
      body { background: linear-gradient(45deg, #667eea, #764ba2); }
      h1 { color: white; text-align: center; padding: 100px; }
    </style>
  </head>
  <body>
    <h1 id="title">Hello Ferrum!</h1>
    <script>
      document.getElementById('title').textContent = 
        'Generated at ' + new Date().toLocaleTimeString();
    </script>
  </body>
  </html>
HTML

# Method 1: Data URL
require 'base64'
data_url = "data:text/html;base64,#{Base64.strict_encode64(html)}"
browser.goto(data_url)
browser.screenshot(path: 'custom.png')

# Method 2: Temporary file
File.write('temp.html', html)
browser.goto("file://#{File.absolute_path('temp.html')}")
browser.screenshot(path: 'custom2.png')
```

### Chart Generation (Chart.js)

```ruby
chart_html = <<~HTML
  <!DOCTYPE html>
  <html>
  <head>
    <script src="https://cdn.jsdelivr.net/npm/chart.js"></script>
  </head>
  <body>
    <canvas id="chart" width="800" height="400"></canvas>
    <script>
      new Chart(document.getElementById('chart'), {
        type: 'line',
        data: {
          labels: ['Jan', 'Feb', 'Mar', 'Apr', 'May'],
          datasets: [{
            label: 'Revenue',
            data: [12, 19, 3, 5, 2],
            borderColor: 'rgb(75, 192, 192)'
          }]
        }
      });
    </script>
  </body>
  </html>
HTML

browser.goto("data:text/html;base64,#{Base64.strict_encode64(chart_html)}")
sleep 2  # Wait for Chart.js to render
browser.screenshot(path: 'chart.png')
```

### Full Page Screenshot

```ruby
browser.goto('https://example.com')

# Get full page height
height = browser.evaluate('document.documentElement.scrollHeight')

# Resize viewport to full height
browser.resize(width: 1920, height: height)

# Capture full page
browser.screenshot(path: 'fullpage.png', full: true)
```

### Wait for Elements

```ruby
browser.goto('https://example.com')

# Wait for element to appear
browser.at_css('#my-element')

# Wait with timeout
browser.at_css('#slow-element', wait: 10)

# Custom wait condition
browser.wait_for_idle(timeout: 5)
```

### Execute JavaScript

```ruby
# Simple evaluation
result = browser.evaluate('2 + 2')  # => 4

# Complex expressions
result = browser.evaluate(<<~JS)
  document.querySelectorAll('a').length
JS

# Async execution
browser.execute(<<~JS)
  console.log('This runs but doesnt return');
  alert('Hello!');
JS
```

### Cookies & Storage

```ruby
# Set cookie
browser.cookies.set(name: 'session', value: 'abc123', domain: 'example.com')

# Get cookies
cookies = browser.cookies.all
puts cookies.inspect

# Clear cookies
browser.cookies.clear

# Local storage
browser.evaluate('localStorage.setItem("key", "value")')
value = browser.evaluate('localStorage.getItem("key")')
```

### Network Control

```ruby
# Block requests
browser.network.intercept
browser.network.on(:request) do |request|
  if request.match?(/ads/)
    request.abort
  else
    request.continue
  end
end

# Monitor network
browser.network.on(:response) do |response|
  puts "#{response.status} #{response.url}"
end
```

## ferrum_demo.rb Features

The included demo (`ferrum_demo.rb`) showcases:

1. **Interactive Clock**: Animated HTML/CSS/JS rendered and captured
2. **Chart Visualization**: Chart.js bar chart generation
3. **JavaScript Execution**: Direct JS evaluation
4. **Multiple Output Formats**: PNG screenshots

## Performance

- **Startup**: ~2-3 seconds (browser launch)
- **Screenshot**: ~100-500ms depending on page complexity
- **Memory**: ~100-200MB per browser instance
- **Concurrent**: Can run multiple browsers in parallel

## Comparison

| Feature | Ferrum | Selenium | Puppeteer |
|---------|--------|----------|-----------|
| Language | Ruby | Multiple | JavaScript |
| Speed | Fast | Slow | Fast |
| Setup | Gem only | Driver + Gem | npm |
| Protocol | CDP | WebDriver | CDP |
| Chrome-only | Yes | No | Yes |

## Common Pitfalls

1. **Chromium not found**: Ensure Chrome/Chromium installed
2. **Timeout errors**: Increase timeout or add explicit waits
3. **Element not found**: Page may not be fully loaded
4. **Memory leaks**: Always call `browser.quit` when done
5. **Sandbox issues**: On Docker/CI, use `'no-sandbox': nil`

## OpenBSD Specific

```bash
# Install Chromium
doas pkg_add chromium

# Install Ferrum
gem install ferrum

# Run demo
ruby ferrum_demo.rb
```

Chromium path may need explicit config:

```ruby
browser = Ferrum::Browser.new(
  browser_path: '/usr/local/bin/chrome',  # OpenBSD path
  headless: true
)
```

## Integration with Postpro

You could extend postpro.rb to:

1. Generate HTML previews of processed images
2. Create before/after comparison galleries
3. Export processing reports as PDFs
4. Generate social media preview cards
5. Create animated slideshows

Example:

```ruby
def generate_preview_gallery(processed_images)
  html = <<~HTML
    <!DOCTYPE html>
    <html>
    <head>
      <style>
        .gallery { display: grid; grid-template-columns: repeat(3, 1fr); gap: 20px; }
        img { width: 100%; border-radius: 10px; box-shadow: 0 4px 6px rgba(0,0,0,0.1); }
      </style>
    </head>
    <body>
      <h1>Postpro Gallery</h1>
      <div class="gallery">
        #{processed_images.map { |img| "<img src='#{img}'>" }.join}
      </div>
    </body>
    </html>
  HTML

  browser = Ferrum::Browser.new(headless: true)
  browser.goto("data:text/html;base64,#{Base64.strict_encode64(html)}")
  browser.screenshot(path: 'gallery_preview.png')
  browser.quit
end
```

## Resources

- **GitHub**: https://github.com/rubycdp/ferrum
- **Documentation**: https://www.rubydoc.info/gems/ferrum
- **Chrome DevTools Protocol**: https://chromedevtools.github.io/devtools-protocol/

## License

See repository LICENSE file.
