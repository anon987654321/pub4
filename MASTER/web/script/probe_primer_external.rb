#!/usr/bin/env ruby
# frozen_string_literal: true

require "ferrum"
require "json"

URL = ARGV[0] || ENV.fetch("WEB_URL", "https://ai.brgen.no/")
CHROME_PATHS = [
  ENV["CHROME_PATH"],
  "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
  "/Applications/Chromium.app/Contents/MacOS/Chromium",
  "/usr/local/bin/chromium",
  "/usr/local/bin/chrome"
].compact.freeze

chrome = CHROME_PATHS.find { |path| File.executable?(path) }
abort("probe_primer: no Chrome executable") unless chrome

failures = []
console_msgs = []

browser = Ferrum::Browser.new(
  browser_path: chrome,
  headless: "new",
  timeout: 180,
  process_timeout: 60,
  browser_options: {
    "no-sandbox" => nil,
    "disable-dev-shm-usage" => nil,
    "ignore-certificate-errors" => nil
  }
)

browser.on(:console) do |msg|
  console_msgs << "[#{msg.type}] #{msg.args.map(&:value).join(' ')}"
rescue StandardError
  nil
end

browser.evaluate_on_new_document(<<~JS)
  window._errs = [];
  window.onerror = function(msg, src, line) {
    window._errs.push(msg + ' @ ' + (src || '').split('/').pop() + ':' + line);
  };
  window.addEventListener('unhandledrejection', function(e) {
    window._errs.push('UNHANDLED: ' + String(e.reason));
  });
JS

puts "probe_primer: #{URL}"

begin
  begin
    browser.go_to(URL)
  rescue Ferrum::PendingConnectionsError => e
    puts "WARN: pending connections on load — #{e.message}"
  end

  sleep 15

  before = browser.evaluate(<<~JS)
    ({
      primer: !!document.getElementById('primer'),
      primerTitle: (document.getElementById('primer-title') || {}).textContent || '',
      primerFired: !!window._primerFired,
      masterFace: typeof window.MASTER_FACE,
      sseBeforeTap: typeof window.EventSource !== 'undefined',
      errs: window._errs || []
    })
  JS

  puts "\n=== before tap ==="
  puts JSON.pretty_generate(before)
  failures << "primer missing before tap" unless before["primer"]
  failures << "js errors before tap" unless before["errs"].to_a.empty?

  rect = browser.evaluate(<<~JS)
    (function() {
      var p = document.getElementById('primer');
      if (!p) return null;
      var r = p.getBoundingClientRect();
      return { x: r.left + r.width / 2, y: r.top + r.height / 2, w: r.width, h: r.height };
    })()
  JS

  puts "primer rect: #{rect.inspect}"

  if rect && rect["w"].to_f.positive?
    browser.mouse.click(x: rect["x"], y: rect["y"])
  else
    browser.mouse.click(x: 200, y: 400)
  end

  sleep 15

  after = browser.evaluate(<<~JS)
    ({
      primer: !!document.getElementById('primer'),
      primerTitle: (document.getElementById('primer-title') || {}).textContent || '',
      primerFired: !!window._primerFired,
      faceSession: document.body.classList.contains('face-session'),
      zshLive: document.getElementById('zsh')?.classList.contains('live'),
      masterFace: typeof window.MASTER_FACE,
      primerFiredProp: window.MASTER_FACE?.primerFired,
      uiStatus: (document.getElementById('ui-status') || {}).textContent || '',
      errorLive: (document.getElementById('error-live') || {}).textContent || '',
      errs: window._errs || []
    })
  JS

  puts "\n=== after tap ==="
  puts JSON.pretty_generate(after)

  failures << "primer not fired" unless after["primerFired"]
  failures << "primer still visible" if after["primer"]
  failures << "face-session missing" unless after["faceSession"]
  failures << "zsh not live" unless after["zshLive"]
  failures << "MASTER_FACE missing" unless after["masterFace"] == "object"
  failures << "js errors after tap" unless after["errs"].to_a.empty?

  puts "\n=== console tail ==="
  console_msgs.last(20).each { |line| puts line } unless console_msgs.empty?

  if failures.empty?
    puts "\nprobe_primer: PASS"
  else
    puts "\nprobe_primer: FAIL"
    failures.each { |f| puts "  - #{f}" }
    exit 1
  end
ensure
  browser&.quit
end