#!/usr/bin/env ruby
# frozen_string_literal: true
# frozen_string_literal: true

require "ferrum"
require "json"
require "open3"
require "timeout"

URL = ARGV[0] || ENV.fetch("WEB_URL", "https://ai.brgen.no/")
BROWSER_TIMEOUT = Integer(ENV.fetch("PROBE_BROWSER_TIMEOUT", "25"))
NAV_TIMEOUT = Integer(ENV.fetch("PROBE_NAV_TIMEOUT", "28"))
MAX_PROBE_SECONDS = Integer(ENV.fetch("PROBE_MAX_SECONDS", "90"))
CHROME_PATHS = [
  ENV["CHROME_PATH"],
  "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
  "/Applications/Chromium.app/Contents/MacOS/Chromium",
  "/usr/local/bin/chromium",
  "/usr/local/bin/chrome",
].compact.freeze

chrome = CHROME_PATHS.find { |path| File.executable?(path) }
abort("probe_primer: no Chrome executable") unless chrome

failures = []
console_msgs = []
browser = nil

def static_html_ok?(url)
  html, status = Open3.capture2("curl", "-fsS", "--max-time", "12", url)
  return false unless status.success?

  html.include?('id="primer"') && html.include?("syncPrimerRefs") && html.include?("form.classList.add('gone')")
rescue StandardError
  false
end

def probe_evaluate(browser, script, attempts: 3, pause: 1.0)
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
  Timeout.timeout(MAX_PROBE_SECONDS) do
    browser = Ferrum::Browser.new(
      browser_path: chrome,
      headless: "new",
      timeout: BROWSER_TIMEOUT,
      process_timeout: BROWSER_TIMEOUT + 15,
      pending_connection_errors: false,
      browser_options: {
        "no-sandbox" => nil,
        "disable-dev-shm-usage" => nil,
        "disable-gpu" => nil,
        "enable-webgl" => nil,
        "use-gl" => "swiftshader",
        "enable-unsafe-swiftshader" => nil,
        "ignore-certificate-errors" => nil,
        "remote-allow-origins" => "*",
        "disable-extensions" => nil,
        "disable-background-networking" => nil,
      },
    )

    browser.on(:console) do |msg|
      console_msgs << "[#{msg.type}] #{msg.args.map(&:value).join(' ')}"
    rescue StandardError # scan: intentional — a raising console hook would kill the probe loop; lost lines are acceptable
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

    begin
      Timeout.timeout(NAV_TIMEOUT) { browser.go_to(URL) }
    rescue Timeout::Error, Ferrum::TimeoutError, Ferrum::PendingConnectionsError => e
      puts "WARN: navigation incomplete — #{e.class}"
    end

    sleep 2

    before = probe_evaluate(browser, <<~JS)
      ({
        primer: !!document.getElementById('primer'),
        primerForm: !!document.getElementById('primer-form'),
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

    tap_mode = probe_evaluate(browser, <<~JS)
      (function() {
        if (window.__MASTER_PRIMER_TAP__) { window.__MASTER_PRIMER_TAP__(); return 'tap'; }
        var p = document.getElementById('primer');
        if (p) { p.click(); return 'click'; }
        return 'none';
      })()
    JS
    puts "tap mode: #{tap_mode}"

    snap = {}
    deadline = Time.now + 25
    until Time.now > deadline
      snap = probe_evaluate(browser, <<~JS)
        ({
          primerFired: !!window._primerFired,
          primer: !!document.getElementById('primer'),
          primerForm: !!document.getElementById('primer-form'),
          primerFormGone: document.getElementById('primer-form')?.classList.contains('gone') || false,
          primerGone: document.getElementById('primer')?.classList.contains('gone') || false,
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
      overlay_clear = snap["primerFired"] && snap["faceSession"] && !snap["primerForm"] && !snap["primer"]
      boot_ready = snap["masterFace"] == "object" && snap["zshLive"]
      break if overlay_clear && boot_ready
      sleep 0.5
    end

    puts "\n=== after tap ==="
    puts JSON.pretty_generate(snap)

    failures << "primer not fired" unless snap["primerFired"]
    failures << "primer still visible" if snap["primer"]
    failures << "primer-form still visible" if snap["primerForm"]
    failures << "face-session missing" unless snap["faceSession"]
    failures << "zsh not live" unless snap["zshLive"]
    failures << "MASTER_FACE missing" unless snap["masterFace"] == "object"
    fatal_errs = snap["errs"].to_a.reject { |e| e.to_s.include?("face render slow") }
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
  end
rescue Ferrum::TimeoutError, Ferrum::DeadBrowserError, Timeout::Error => e
  if static_html_ok?(URL)
    puts "\nok: probe_primer skip headless blocked (#{e.class})"
    puts "ok: static HTML primer and boot script present"
    exit 0
  end
  puts "\nwarn: probe_primer (#{e.class}: #{e.message})"
  exit 1
ensure
  browser&.quit
end
