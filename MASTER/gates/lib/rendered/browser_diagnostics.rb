# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "tmpdir"
require "time"
require "uri"
require "yaml"
require_relative "../../../lib/gap"
require_relative "../../support/gate_result"
require_relative "../../support/geometry_probe"

module Deploy
  # Browser-runtime evidence for the canonical RAILS surface inventory.
  #
  # This intentionally uses the shared stdlib CDP client rather than adding a
  # second browser stack. Each declared route/viewport gets its own clean guest
  # navigation, runtime/network record, and screenshot. Existing layout_snapshot
  # remains the approved structural baseline; these PNGs are diagnostic evidence,
  # not an automatically accepted visual baseline.
  class BrowserDiagnosticsGate
    ROOT = File.expand_path("../../../..", __dir__).freeze
    DEFAULT_OUTPUT = File.join(Dir.tmpdir, "pub4-browser-diagnostics").freeze
    DEFAULT_SETTLE_MS = 500
    MAX_SETTLE_MS = 5_000
    HARD_HTTP_STATUS = 500

    def self.run = new.run

    def self.grade(surface:, status:, console_messages:, http_failures:, request_failures:, browser_error: false)
      hard = []
      soft = []

      Array(console_messages).each do |message|
        level = message[:level].to_s
        text = [message[:source], message[:text], message[:url]].reject { |part| part.to_s.empty? }.join(": ")
        next if text.empty?

        if level == "error" && message[:source].to_s == "exception"
          hard << "uncaught JavaScript exception: #{text}"
        elsif level == "error"
          # The existing visual contract keeps ordinary console errors soft until
          # the live error budget has been measured across the whole route matrix.
          soft << "browser console error: #{text}"
        elsif level == "warning"
          soft << "browser console warning: #{text}"
        end
      end

      if browser_error
        hard << "Chromium rendered its internal network-error page"
      elsif status.to_i >= 400
        hard << "document returned HTTP #{status}"
      elsif status.to_i.zero?
        soft << "document response status unavailable"
      end

      Array(http_failures).each do |failure|
        status_code = failure[:status].to_i
        url = failure[:url].to_s
        next unless status_code >= 400

        message = "HTTP #{status_code} #{url} (#{failure[:resource_type]})"
        if owned_url?(surface, url) && status_code >= HARD_HTTP_STATUS
          hard << "first-party resource failed: #{message}"
        else
          soft << "resource returned an error: #{message}"
        end
      end

      Array(request_failures).each do |failure|
        url = failure[:url].to_s
        message = "#{url} — #{failure[:error]}"
        if owned_url?(surface, url)
          soft << "first-party request failed: #{message}"
        else
          soft << "external request failed: #{message}"
        end
      end

      { hard: hard.uniq, soft: soft.uniq }
    end

    def self.owned_url?(surface, url)
      host = URI.parse(url).host.to_s.downcase
      return false if host.empty?

      first_party_hosts = [URI.parse(surface.url).host.to_s.downcase]
      first_party_hosts << app_domains.fetch(surface.app.to_s, nil)
      if surface.app.to_s == "brgen"
        # Read hosts from the same route inventory the browser actually visits;
        # do not infer app ownership from a broad suffix such as *.brgen.no.
        first_party_hosts.concat(BrgenVerticalSurfaces::SURFACES.map { |row| row[:host] })
      end
      first_party_hosts.compact.map { |value| value.to_s.downcase }.include?(host)
    rescue URI::InvalidURIError, KeyError, SystemCallError
      false
    end

    def self.app_domains
      @app_domains ||= YAML.safe_load_file(File.join(ROOT, "RAILS", "apps.yml"))
                            .fetch("apps").to_h do |name, app|
        [name.to_s, app["domain"].to_s.downcase]
      end
    end

    def run
      @result = GateResult.new
      unless GeometryProbe.available?
        @result.inconclusive!("browser_diagnostics: no Chrome/Chromium — browser runtime not measured",
                              gap: Master::Gap::NO_BROWSER)
        return @result
      end

      surfaces = GeometryProbe.surfaces
      if surfaces.empty?
        @result.inconclusive!("browser_diagnostics: route inventory selected no surfaces")
        return @result
      end

      live = GeometryProbe.reachable(surfaces)
      live_ids = live.to_h { |surface| [surface.id, true] }
      GeometryProbe.unreachable_apps(surfaces).each do |app|
        @result.skipped_live("browser_diagnostics: #{app} port closed — route/viewport cells skipped")
      end
      if live.empty?
        @result.inconclusive!("browser_diagnostics: no RAILS app is reachable — nothing navigated")
        return @result
      end

      run_id = Time.now.utc.strftime("%Y%m%dT%H%M%SZ-#{Process.pid}")
      base = File.expand_path(ENV.fetch("GATE_BROWSER_DIAGNOSTICS_OUTPUT", DEFAULT_OUTPUT))
      output = File.join(base, run_id)
      screenshot_dir = File.join(output, "screenshots")
      begin
        FileUtils.mkdir_p(screenshot_dir)
      rescue SystemCallError => e
        @result.fail("browser_diagnostics: evidence delivery failed to create #{screenshot_dir} — #{e.class}: #{e.message}")
        return @result
      end
      settle_ms = Integer(ENV.fetch("GATE_BROWSER_DIAGNOSTICS_SETTLE_MS", DEFAULT_SETTLE_MS.to_s)).clamp(0, MAX_SETTLE_MS)
      rows = []

      GeometryProbe.with_browser(root: ROOT, warm: live) do |cdp|
        surfaces.each do |surface|
          unless live_ids[surface.id]
            rows << skipped_row(surface)
            next
          end

          rows << capture_surface(cdp, surface, screenshot_dir, settle_ms)
        end
      end

      manifest = File.join(output, "manifest.json")
      payload = {
        schema: 1,
        generated_at: Time.now.utc.iso8601,
        run_id: run_id,
        browser: Deploy::CdpSession.chrome_path.to_s,
        source_inventory: "MASTER/gates/data/geometry_surfaces.yml",
        screenshots: "viewport PNG per measured route/viewport",
        results: rows,
        summary: rows.group_by { |row| row.fetch("status") }.transform_values(&:length)
      }
      begin
        File.write(manifest, JSON.pretty_generate(payload) + "\n")
      rescue SystemCallError => e
        @result.fail("browser_diagnostics: evidence delivery failed to write #{manifest} — #{e.class}: #{e.message}")
        return @result
      end

      measured = rows.count { |row| %w[PASS FAIL].include?(row.fetch("status")) }
      @result.checked!(measured)
      if measured.zero?
        @result.inconclusive!("browser_diagnostics: no route produced a conclusive browser result")
        return @result
      end
      @result.warn("browser_diagnostics: #{measured}/#{rows.size} route/viewport cells measured")
      @result.warn("browser_diagnostics: evidence manifest #{manifest}")
      @result
    rescue CdpSession::Unavailable, CdpSession::Error, SystemCallError => e
      @result ||= GateResult.new
      @result.inconclusive!("browser_diagnostics: Chrome/CDP could not complete the inventory (#{e.class}: #{e.message})")
    end

    private

    def skipped_row(surface)
      {
        "app" => surface.app,
        "surface" => surface.label,
        "viewport" => surface.viewport,
        "url" => surface.url,
        "status" => "SKIPPED",
        "reason" => "app port is closed"
      }.tap do |row|
        puts "browser0: #{surface.id} SKIPPED — app port is closed"
      end
    end

    def capture_surface(cdp, surface, screenshot_dir, settle_ms)
      cdp.viewport(surface.width, surface.height, mobile: surface.width < 500)
      cdp.headers(GeometryProbe::PROBE_HEADERS)
      cdp.clear_cookies
      cdp.clear_events

      navigation_error = nil
      begin
        cdp.navigate(surface.url, settle: settle_ms / 1000.0)
      rescue CdpSession::Error, SystemCallError => e
        navigation_error = "#{e.class}: #{e.message}"
      end

      status = safely { cdp.status }
      title = safely { cdp.evaluate("document.title") }
      browser_error = safely { cdp.evaluate("location.protocol === 'chrome-error:'") } == true
      slug = [surface.app, surface.label, surface.viewport].map { |part| safe_slug(part) }.join("-")
      screenshot = File.join(screenshot_dir, "#{slug}.png")
      screenshot_error = capture_screenshot(cdp, screenshot)
      screenshot_sha256 = Digest::SHA256.file(screenshot).hexdigest if File.file?(screenshot)

      # Screenshot CDP itself drains the event stream; read the evidence after it
      # so late asset failures and uncaught exceptions are not lost to a race.
      messages = cdp.console_messages
      http_errors = cdp.http_failures
      request_errors = cdp.request_failures
      verdict = self.class.grade(
        surface:,
        status:,
        console_messages: messages,
        http_failures: http_errors,
        request_failures: request_errors,
        browser_error:
      )

      verdict[:hard] << "navigation failed: #{navigation_error}" if navigation_error
      verdict[:hard] << "screenshot failed: #{screenshot_error}" if screenshot_error
      verdict[:hard].uniq!
      status_label = verdict[:hard].empty? ? "PASS" : "FAIL"
      verdict[:soft].each { |message| @result.fail("browser_diagnostics: #{surface.id} — #{message}", severity: :soft) }
      verdict[:hard].each { |message| @result.fail("browser_diagnostics: #{surface.id} — #{message}") }

      row = {
        "app" => surface.app,
        "surface" => surface.label,
        "viewport" => surface.viewport,
        "dimensions" => [surface.width, surface.height],
        "url" => surface.url,
        "status" => status_label,
        "http_status" => status,
        "title" => title,
        "console_messages" => messages,
        "http_failures" => http_errors,
        "request_failures" => request_errors,
        "failure_reasons" => verdict[:hard].uniq,
        "warnings" => verdict[:soft],
        "screenshot" => screenshot_sha256 ? screenshot : nil,
        "screenshot_sha256" => screenshot_sha256,
        "screenshot_error" => screenshot_error
      }
      print_row(surface, row)
      row
    rescue CdpSession::Error, SystemCallError => e
      @result.inconclusive!("browser_diagnostics: #{surface.id} CDP could not complete — #{e.class}: #{e.message}")
      row = {
        "app" => surface.app,
        "surface" => surface.label,
        "viewport" => surface.viewport,
        "url" => surface.url,
        "status" => "INCONCLUSIVE",
        "reason" => "#{e.class}: #{e.message}"
      }
      puts "browser0: #{surface.id} INCONCLUSIVE — #{row.fetch('reason')}"
      row
    end

    def capture_screenshot(cdp, path)
      cdp.screenshot(path)
      nil
    rescue CdpSession::Error, SystemCallError => e
      "#{e.class}: #{e.message}"
    end

    def safely
      yield
    rescue CdpSession::Error, SystemCallError
      nil
    end

    def safe_slug(value)
      value.to_s.gsub(/[^a-zA-Z0-9_-]+/, "_").sub(/\A_+/, "").sub(/_+\z/, "")
    end

    def print_row(surface, row)
      counts = [
        "http=#{row['http_status'] || 'unknown'}",
        "console_errors=#{row['console_messages'].count { |item| item[:level].to_s == 'error' }}",
        "http_failures=#{row['http_failures'].size}",
        "request_failures=#{row['request_failures'].size}"
      ]
      detail = row["failure_reasons"].empty? ? counts.join(" ") : row["failure_reasons"].join("; ")
      detail += " screenshot=#{row['screenshot']}" if row["screenshot"]
      puts "browser0: #{surface.id} #{row['status']} — #{detail}"
    end
  end
end
