# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "tmpdir"
require "time"
require "uri"

require "yaml"
require_relative "../../../lib/gap"
require_relative "../../support/check_result"
require_relative "../../support/png_diff"
require_relative "../../support/geometry_probe"
require_relative "../../support/sweep_replay"

module Deploy
  # Browser-runtime evidence for the canonical RAILS surface inventory.
  #
  # This intentionally uses the shared stdlib CDP client rather than adding a
  # second browser stack. Each declared route/viewport gets its own clean guest
  # navigation, runtime/network record, and screenshot. Committed structural
  # snapshots remain authoritative; opted-in surfaces also compare against
  # separately approved PNG baselines. Normal /fix and autofix never bless PNGs.
  class BrowserDiagnosticsCheck
    ROOT = File.expand_path("../../../..", __dir__).freeze

    DEFAULT_OUTPUT = File.join(Dir.tmpdir, "pub4-browser-diagnostics").freeze
    DEFAULT_SETTLE_MS = 500
    MAX_SETTLE_MS = 5_000
    HARD_HTTP_STATUS = 500
    CRITICAL_RESOURCE_TYPES = %w[Script Stylesheet].freeze
    VISUAL_BASELINE_DIR = File.join(ROOT, "MASTER", "checks", "data", "visual_baselines").freeze
    DEFAULT_PIXEL_DIFF_MAX_RATIO = "0.01".freeze

    def self.run = new.run

    def self.pixel_baseline_strict?(env = ENV)
      %w[1 true yes on].include?(env["CHECK_PIXEL_BASELINE_STRICT"].to_s.strip.downcase)
    end

    def self.pixel_diff_max_ratio(env = ENV)
      raw = env.fetch("CHECK_PIXEL_DIFF_MAX_RATIO", DEFAULT_PIXEL_DIFF_MAX_RATIO)
      number = Float(raw, exception: false)
      return number if number&.finite? && number.between?(0.0, 1.0)

      raise ArgumentError, "CHECK_PIXEL_DIFF_MAX_RATIO must be finite and between 0 and 1"
    end

    def self.visual_baseline_path(surface)
      return unless surface.pixel_snapshot

      File.join(VISUAL_BASELINE_DIR, "#{surface_slug(surface)}.png")
    end

    # One spelling for the screenshot and its approved baseline, so the two
    # names cannot drift apart.
    def self.surface_slug(surface)
      [surface.app, surface.label, surface.viewport].map { |part| part.to_s.gsub(/[^a-zA-Z0-9_-]+/, "_").sub(/\A_+/, "").sub(/_+\z/, "") }.join("-")
    end

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
        critical_asset = CRITICAL_RESOURCE_TYPES.include?(failure[:resource_type].to_s)
        if owned_url?(surface, url) && (status_code >= HARD_HTTP_STATUS || critical_asset)
          hard << "first-party resource failed: #{message}"
        else
          soft << "resource returned an error: #{message}"
        end
      end

      Array(request_failures).each do |failure|
        url = failure[:url].to_s
        message = "#{url} — #{failure[:error]}"

        if owned_url?(surface, url) && CRITICAL_RESOURCE_TYPES.include?(failure[:resource_type].to_s)
          hard << "first-party executable request failed: #{message}"
        elsif owned_url?(surface, url)
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
      @result = CheckResult.new
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

      base = File.expand_path(ENV.fetch("CHECK_BROWSER_DIAGNOSTICS_OUTPUT", DEFAULT_OUTPUT))
      replay = SweepReplay.new(base:)
      key = replay.key(SweepReplay.inputs(root: ROOT, check_code: __FILE__, live_ids: live.map(&:id)))
      recorded = replay.rows(key)
      return replayed(recorded, since: replay.recorded_at(key)) if recorded

      run_id = Time.now.utc.strftime("%Y%m%dT%H%M%SZ-#{Process.pid}")
      output = File.join(base, run_id)
      screenshot_dir = File.join(output, "screenshots")
      begin
        FileUtils.mkdir_p(screenshot_dir)
      rescue SystemCallError => e
        @result.fail("browser_diagnostics: evidence delivery failed to create #{screenshot_dir} — #{e.class}: #{e.message}")

        return @result
      end
      settle_ms = Integer(ENV.fetch("CHECK_BROWSER_DIAGNOSTICS_SETTLE_MS", DEFAULT_SETTLE_MS.to_s)).clamp(0, MAX_SETTLE_MS)
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
        run_id:,
        browser: Deploy::CdpSession.chrome_path.to_s,
        source_inventory: "MASTER/checks/data/geometry_surfaces.yml",
        screenshots: "viewport PNG per measured route/viewport",
        results: rows,
        summary: rows.group_by { |row| row.fetch("status") }.transform_values(&:length),
      }

      begin
        File.write(manifest, JSON.pretty_generate(payload) + "\n")
      rescue SystemCallError => e
        @result.fail("browser_diagnostics: evidence delivery failed to write #{manifest} — #{e.class}: #{e.message}")
        return @result
      end

      replay.remember(key:, manifest:)
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
      @result ||= CheckResult.new
      @result.inconclusive!("browser_diagnostics: Chrome/CDP could not complete the inventory (#{e.class}: #{e.message})")
    end

    # The recorded sweep's verdicts, as the rendered one would have reported them.
    def replayed(rows, since:)
      @result ||= CheckResult.new
      print_replay(since)
      rows.each { |row| replay_row(row) }

      measured = rows.count { |row| %w[PASS FAIL].include?(row["status"]) }
      @result.checked!(measured)
      @result.warn("browser_diagnostics: #{measured}/#{rows.size} route/viewport cells replayed, RAILS unchanged")
      @result
    end

    private

    def print_replay(since) = puts("browser0: RAILS unchanged since #{since.strftime("%H:%M")}, replaying that sweep")

    def replay_row(row)
      id = [row["app"], row["surface"], row["viewport"]].join("/")
      return @result.inconclusive!("browser_diagnostics: #{id} #{row["reason"]}") if row["status"] == "INCONCLUSIVE"

      Array(row["warnings"]).each { |message| @result.fail("browser_diagnostics: #{id} — #{message}", severity: :soft) }
      Array(row["failure_reasons"]).each { |message| @result.fail("browser_diagnostics: #{id} — #{message}") }
    end

    def skipped_row(surface)
      {
        "app" => surface.app,
        "surface" => surface.label,
        "viewport" => surface.viewport,
        "url" => surface.url,
        "status" => "SKIPPED",
        "reason" => "app port is closed",
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
      screenshot = File.join(screenshot_dir, "#{self.class.surface_slug(surface)}.png")
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
        browser_error:,
      )

      verdict[:hard] << "navigation failed: #{navigation_error}" if navigation_error
      verdict[:hard] << "screenshot failed: #{screenshot_error}" if screenshot_error
      runtime_failures = verdict[:hard].uniq
      runtime_status = runtime_failures.empty? ? "PASS" : "FAIL"
      pixel = pixel_evidence(surface:, screenshot:, screenshot_dir:, screenshot_error:)
      if %w[REGRESSION DIMENSION_MISMATCH].include?(pixel["status"])
        verdict[:hard] << pixel.fetch("reason")
      elsif %w[MISSING UNSUPPORTED].include?(pixel["status"])
        message = pixel.fetch("reason")

        if self.class.pixel_baseline_strict?
          verdict[:hard] << message
        else
          verdict[:soft] << message
        end
      end

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
        "runtime_status" => runtime_status,
        "runtime_failure_reasons" => runtime_failures,
        "http_status" => status,
        "title" => title,
        "console_messages" => messages,
        "http_failures" => http_errors,
        "request_failures" => request_errors,
        "failure_reasons" => verdict[:hard].uniq,
        "warnings" => verdict[:soft],
        "screenshot" => screenshot_sha256 ? screenshot : nil,
        "screenshot_sha256" => screenshot_sha256,
        "screenshot_error" => screenshot_error,
        "pixel_baseline_status" => pixel["status"],
        "pixel_baseline" => pixel["baseline"],
        "pixel_diff_count" => pixel["pixel_diff_count"],
        "pixel_diff_ratio" => pixel["pixel_diff_ratio"],
        "pixel_diff_image" => pixel["pixel_diff_image"],
        "pixel_diff_max_ratio" => pixel["max_ratio"],
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
        "reason" => "#{e.class}: #{e.message}",
      }

      puts "browser0: #{surface.id} INCONCLUSIVE — #{row.fetch('reason')}"
      row
    end

    def pixel_evidence(surface:, screenshot:, screenshot_dir:, screenshot_error:)
      baseline = self.class.visual_baseline_path(surface)
      return { "status" => "NOT_TRACKED" } unless baseline
      return { "status" => "UNMEASURED", "baseline" => baseline } if screenshot_error || !File.file?(screenshot)

      unless File.file?(baseline)
        return { "status" => "MISSING", "baseline" => baseline,
                 "reason" => "pixel baseline missing for #{surface.id}; review a capture, then promote it with MASTER/tools/approve_visual_baselines.rb" }
      end

      max_ratio = self.class.pixel_diff_max_ratio
      slug = File.basename(screenshot, ".png")
      diff_path = File.join(screenshot_dir, "#{slug}-pixel-diff.png")
      compared = PngDiff.compare(baseline_path: baseline, current_path: screenshot, diff_path:)

      common = {
        "baseline" => baseline,
        "pixel_diff_count" => compared[:pixel_diff_count],
        "pixel_diff_ratio" => compared[:pixel_diff_ratio],
        "pixel_diff_image" => compared[:pixel_diff_image],
        "max_ratio" => max_ratio,
      }

      if compared[:status] == :dimension_mismatch
        common.merge("status" => "DIMENSION_MISMATCH",
                     "reason" => "pixel baseline dimensions changed for #{surface.id}: #{compared[:baseline_dimensions].join('x')} to #{compared[:current_dimensions].join('x')}")
      elsif compared[:pixel_diff_ratio] > max_ratio
        common.merge("status" => "REGRESSION",
                     "reason" => "pixel regression for #{surface.id}: #{compared[:pixel_diff_count]} changed pixels (#{(compared[:pixel_diff_ratio] * 100).round(3)}%) exceeds #{(max_ratio * 100).round(3)}% budget; diff=#{compared[:pixel_diff_image]}")
      else
        common.merge("status" => "COMPARED")
      end
    rescue PngDiff::InvalidPng => e
      { "status" => "UNSUPPORTED", "baseline" => baseline,
        "reason" => "pixel baseline could not be compared for #{surface.id}: #{e.class}: #{e.message}" }
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

    def print_row(surface, row)
      counts = [
        "http=#{row['http_status'] || 'unknown'}",
        "console_errors=#{row['console_messages'].count { |item| item[:level].to_s == 'error' }}",
        "http_failures=#{row['http_failures'].size}",
        "request_failures=#{row['request_failures'].size}",
      ]

      detail = row["failure_reasons"].empty? ? counts.join(" ") : row["failure_reasons"].join("; ")
      pixel_status = row["pixel_baseline_status"]
      if %w[COMPARED REGRESSION DIMENSION_MISMATCH MISSING UNSUPPORTED].include?(pixel_status)
        detail += " pixel=#{pixel_status}"

        if row["pixel_diff_ratio"]
          detail += " changed_pixels=#{row['pixel_diff_count']} drift=#{(row['pixel_diff_ratio'] * 100).round(4)}%"
          detail += " budget=#{(row['pixel_diff_max_ratio'] * 100).round(3)}%" if row["pixel_diff_max_ratio"]
        end
        detail += " diff=#{row['pixel_diff_image']}" if row["pixel_diff_image"]
      end

      detail += " screenshot=#{row['screenshot']}" if row["screenshot"]
      puts "browser0: #{surface.id} #{row['status']} — #{detail}"
    end
  end
end
