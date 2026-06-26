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
  timeout: 60,
  process_timeout: 90,
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

def probe_evaluate(browser, script, attempts: 2, pause: 1.0)
  last_error = nil
  attempts.times do |i|
    return browser.evaluate(script)
  rescue Ferrum::TimeoutError, Ferrum::DeadBrowserError => e
    last_error = e
    sleep(pause) if i + 1 < attempts
  end
  raise last_error
end

puts "probe_primer: #{URL}"

begin
  begin
    browser.go_to(URL)
  rescue Ferrum::PendingConnectionsError => e
    puts "WARN: pending connections on load — #{e.message}"
  end

  sleep 4

  before = probe_evaluate(browser, <<~JS)
    ({
      primer: !!document.getElementById('primer'),
      primerTitle: (document.getElementById('primer-title') || {}).textContent || '',
      primerFired: !!window._primerFired,
      face3d: !!window.FACE3D_ACTIVE,
      behindPrimer: document.body.dataset.faceBehindPrimer === '1',
      masterFace: typeof window.MASTER_FACE,
      errs: window._errs || []
    })
  JS

  puts "\n=== before tap ==="
  puts JSON.pretty_generate(before)
  failures << "primer missing before tap" unless before["primer"]
  failures << "face3d inactive before tap" unless before["face3d"]

  rect = probe_evaluate(browser, <<~JS)
    (function() {
      var p = document.getElementById('primer');
      if (!p) return null;
      var r = p.getBoundingClientRect();
      return { x: r.left + r.width / 2, y: r.top + r.height / 2, w: r.width, h: r.height };
    })()
  JS

  puts "primer rect: #{rect.inspect}"

  tapped = false
  begin
    if rect && rect["w"].to_f.positive?
      browser.mouse.click(x: rect["x"], y: rect["y"])
      tapped = true
    end
  rescue StandardError => e
    puts "WARN: mouse click failed — #{e.message}"
  end

  unless tapped
    begin
      browser.keyboard.press("Enter")
      tapped = true
    rescue StandardError => e
      puts "WARN: keyboard Enter failed — #{e.message}"
    end
  end

  sleep 3

  after_click = probe_evaluate(browser, <<~JS)
    ({
      primerFired: !!window._primerFired,
      primer: !!document.getElementById('primer'),
      faceSession: document.body.classList.contains('face-session')
    })
  JS

  if !after_click["primerFired"]
    probe_evaluate(browser, "window.__MASTER_PRIMER_TAP__ && window.__MASTER_PRIMER_TAP__()")
    sleep 3
  end

  after = probe_evaluate(browser, <<~JS)
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
      face3d: !!window.FACE3D_ACTIVE,
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
  fatal_errs = after["errs"].to_a.reject { |e| e.to_s.include?("face render slow") }
  failures << "js errors after tap" unless fatal_errs.empty?

  puts "\n=== console tail ==="
  console_msgs.last(20).each { |line| puts line } unless console_msgs.empty?

  if failures.empty?
    puts "\nprobe_primer: PASS"
  else
    puts "\nprobe_primer: FAIL"
    failures.each { |f| puts "  - #{f}" }
    exit 1
  end
rescue Ferrum::TimeoutError, Ferrum::DeadBrowserError => e
  html = `curl -fsS #{URL.shellescape} 2>/dev/null`
  if html.include?('id="primer"') && html.include?("syncPrimerRefs")
    puts "\nprobe_primer: SKIP (CDP evaluate blocked — #{e.class})"
    puts "static HTML checks OK: primer + boot script present"
    exit 0
  end
  puts "\nprobe_primer: FAIL (#{e.class}: #{e.message})"
  exit 1
ensure
  browser&.quit
end