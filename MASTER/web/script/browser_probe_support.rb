# frozen_string_literal: true

module BrowserProbeSupport
  CHROME_PATHS = [
    ENV["CHROME_PATH"],
    "/usr/local/bin/chromium",
    "/usr/local/bin/chrome",
    "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
    "/Applications/Chromium.app/Contents/MacOS/Chromium"
  ].compact.freeze

  BROWSER_TIMEOUT = Integer(ENV.fetch("PROBE_BROWSER_TIMEOUT", "15"))
  MAX_PROBE_SECONDS = Integer(ENV.fetch("PROBE_MAX_SECONDS", "75"))

  module_function

  def chrome_path
    CHROME_PATHS.find { |path| File.executable?(path) }
  end

  def build_browser(chrome:, timeout: BROWSER_TIMEOUT, pending_connection_errors: false, extra_options: {})
    require "ferrum"
    Ferrum::Browser.new(
      browser_path: chrome,
      headless: "new",
      timeout: timeout,
      process_timeout: timeout + 12,
      pending_connection_errors: pending_connection_errors,
      browser_options: {
        "no-sandbox" => nil,
        "disable-dev-shm-usage" => nil,
        "disable-gpu" => nil,
        "ignore-certificate-errors" => nil,
        "remote-allow-origins" => "*"
      }.merge(extra_options)
    )
  end

  def install_error_hooks(browser, key: "_crawlErrs")
    browser.evaluate_on_new_document(<<~JS)
      window.#{key} = [];
      window.onerror = function(msg, src, line) {
        window.#{key}.push(String(msg) + ' @ ' + (src || '').split('/').pop() + ':' + line);
      };
      window.addEventListener('unhandledrejection', function(e) {
        window.#{key}.push('UNHANDLED: ' + String(e.reason));
      });
    JS
  end

  def evaluate(browser, script, attempts: 3, pause: 1.0)
    attempts.times do |i|
      return browser.evaluate(script)
    rescue Ferrum::TimeoutError, Ferrum::DeadBrowserError => e
      raise e if i + 1 >= attempts
      sleep pause
    end
  end

  def tap_primer(browser)
    evaluate(browser, <<~JS)
      (function() {
        if (window.__MASTER_PRIMER_TAP__) { window.__MASTER_PRIMER_TAP__(); return true; }
        var p = document.getElementById('primer');
        if (p) { p.click(); return true; }
        return false;
      })()
    JS
  end

  def wait_master_session(browser, timeout_s: 20)
    deadline = Time.now + timeout_s
    snap = {}
    until Time.now >= deadline
      snap = evaluate(browser, <<~JS)
        ({
          primerFired: !!window._primerFired,
          faceSession: document.body.classList.contains('face-session'),
          masterFace: typeof window.MASTER_FACE,
          sendMessage: typeof window.sendMessage
        })
      JS
      ready = snap["primerFired"] && snap["faceSession"] && snap["masterFace"] == "object"
      ready &&= snap["sendMessage"] == "function" if snap.key?("sendMessage")
      break if ready
      sleep 1
    end
    snap
  end

  def run_ping_chat(browser, chat_wait_s: 4)
    evaluate(browser, <<~JS)
      (function() {
        if (window.MASTER_CONTAINER?.ready?.() === false) {
          window.MASTER_CONTAINER_READY = true;
          var input = document.getElementById('zin');
          if (input) input.disabled = false;
        }
        window.sendMessage && window.sendMessage('ping');
        return true;
      })()
    JS
    sleep Integer(chat_wait_s)
    evaluate(browser, <<~JS)
      ({
        hasPong: /pong/i.test((document.querySelector('.message.assistant:last-of-type .msg-body')?.textContent || '')),
        logCount: document.querySelectorAll('#chat-log .message').length
      })
    JS
  end

  def fatal_js_errors(browser, key: "_crawlErrs")
    errs = evaluate(browser, "window.#{key} || []")
    Array(errs).reject { |e| e.to_s.include?("face render slow") }
  end
end