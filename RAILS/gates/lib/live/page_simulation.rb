# frozen_string_literal: true

require "json"
require "net/http"
require "uri"
require "yaml"
require_relative "../../../../OPENBSD/lib/deploy_inventory"
require_relative "../../../../OPENBSD/lib/gate_result"
require_relative "../../../tools/crawl_support"
require_relative "../../support/page_inventory"

module Deploy
  # UI/UX user simulation across every full-page Rails surface.
  #
  # Two modes:
  #   1. Source — always runs. Reads each page template and asserts UX floor
  #      (heading, empty CTAs, dead-end risk, guest auth-wall honesty, forms).
  #   2. Live — when the app port is open. Soft-guest HTTP GET of every
  #      guest-open, non-parameterised path; checks status, landmarks, and
  #      exception chrome. Auth-only pages are noted, not hard-failed, when
  #      unauthenticated.
  #
  # Personas: guest (Craigslist-style no-signup) and auth (session expected).
  # Scope: focus triangle — brgen · amber · MASTER web.
  class PageSimulationGate
    ROOT = File.expand_path("../../../..", __dir__)
    REPORT_PATH = File.join(ROOT, "RAILS", "gates", "data", "page_sim_report.yml")
    SNAPSHOT_PATH = File.join(ROOT, "RAILS", "gates", "data", "page_sim_inventory.yml")

    # Auth surfaces where the wall is the product (sign-in / register).
    AUTH_WALL_OK = %r{/session/new|/registration/new|/passwords}

    # MASTER's face is not a Rails app and has no apps.yml row, so its port is
    # the one literal here. The three Rails ports are read from apps.yml rather
    # than restated: a stale copy would not fail this gate, it would point the
    # live half at a closed port and skip every page as unreachable.
    MASTER_PORT = 53_187
    PORTS = Inventory.new(root: ROOT)
      .apps.to_h { |app| [app.name, app.port] }
      .merge("master" => MASTER_PORT)
      .freeze

    def self.run = new.run

    def run
      @result = GateResult.new
      @report = {
        "generated_at" => Time.now.utc.iso8601,
        "pages" => [],
        "summary" => {},
      }

      uncovered = PageInventory.uncovered_shared_views
      @result.fail("page_simulation: shared view outside the inventory — #{uncovered.join(", ")}") if uncovered.any?

      # A stale manifest resolves confidently and wrongly, which is the failure
      # the hand-maintained filename ladder had. Hard, not soft: the fix is one
      # command, and a wrong URL turns every finding on that page into noise.
      PageInventory.stale_route_manifests.each { |message| @result.fail("page_simulation: #{message}") }

      pages = PageInventory.all
      PageInventory.write_snapshot!(SNAPSHOT_PATH)
      by = pages.group_by { |p| p[:app] }.transform_values(&:size)
      @result.warn("page_simulation: inventory #{pages.size} pages #{by.inspect}")

      pages.each { |page| simulate_source(page) }

      ports_open = PORTS.transform_values { |port| CrawlSupport.port_open?("127.0.0.1", port) }
      ports_open.each do |app, open|
        if open
          @result.warn("page_simulation: #{app} port #{PORTS[app]} open")
        else
          @result.skipped_live("page_simulation: #{app} port #{PORTS[app]} closed — live surfaces skipped")
        end
      end

      live_count = 0
      PageInventory.guest_liveable.each do |page|
        port = PORTS[page[:app]]
        next unless ports_open[page[:app]]

        live_count += 1
        simulate_live(page, port)
      end

      if live_count.zero?
        @result.warn("page_simulation: live HTTP skipped (no triangle app listening) — source checks still ran")
      else
        @result.warn("page_simulation: live HTTP on #{live_count} guest surfaces")
      end

      write_report!(pages, ports_open, live_count)
      @result.checked!(pages.size)
      @result
    end

    private

    def simulate_source(page)
      entry = base_entry(page).merge("mode" => "source")
      path = page[:abs_view]
      unless File.file?(path)
        soft_fail(entry, "missing view file")
        push_entry(entry)
        return
      end

      body = File.read(path)
      findings = []

      findings.concat(check_heading(page, body))
      findings.concat(check_empty_cta(page, body))
      findings.concat(check_dead_end(page, body))
      findings.concat(check_auth_wall_source(page, body))
      findings.concat(check_form_labels(page, body))
      findings.concat(check_hardcoded_chrome(page, body))
      findings.concat(check_master_landmarks(page, body))

      findings.each do |f|
        apply_finding(entry, f)
      end
      entry["ok"] = findings.none? { |f| f[:severity] == :hard }
      entry["findings"] = findings.map { |f| f[:message] }
      push_entry(entry)
    end

    def simulate_live(page, port)
      entry = base_entry(page).merge("mode" => "live")
      url = "http://127.0.0.1:#{port}#{page[:path]}"
      response = fetch_with_host(url, host: page[:host])
      code = response.code.to_i
      body = response.body.to_s
      findings = []

      # The header above says auth-only pages are noted rather than hard-failed
      # when unauthenticated, and that was true only for the redirect shape: a
      # controller answering the guest with a 302 to sign-in lands inside
      # 200..399 and passes, while one answering `head :forbidden` was a hard
      # failure for behaving correctly. Dating's verification queue is the
      # second kind — a moderation surface whose index is `head :forbidden
      # unless reviewer?`, so 403 is the right answer to this gate's persona.
      #
      # 404 and 5xx stay hard. Those say the page is missing or broken, which is
      # what this is for.
      if [ 401, 403 ].include?(code)
        findings << soft("HTTP #{code} — auth-only for the guest persona")
      elsif !code.between?(200, 399)
        findings << hard("HTTP #{code} for #{url}#{page[:host] ? " Host=#{page[:host]}" : ""}")
      end

      if body.include?("Exception") || body.include?("Routing Error")
        findings << hard("exception chrome in body")
      end

      if body.include?("<html")
        static_public = page[:path].to_s.end_with?(".html")
        has_main = body.match?(/main-content|<main\b|id="face"|id="zin"|role="main"/i)
        if !has_main
          # MASTER offline/diag/swarm are bare public assets, not app layouts.
          findings << (static_public ? soft("static page missing main landmark") : hard("missing main landmark / face root"))
        end
        has_skip = body.match?(/skip-link|Skip to|#main-content|#zin|id="primer"/i)
        unless has_skip
          if static_public || (page[:app] == "master" && page[:path] != "/" && page[:path] != "/dashboard")
            findings << soft("static/utility page has no skip link")
          else
            findings << hard("missing skip-to-main affordance")
          end
        end
      end

      if page[:persona] == "guest" && !page[:path].match?(AUTH_WALL_OK)
        if body.match?(/Sign in to continue/i)
          findings << hard("auth wall on guest-open surface")
        end
      end

      # Title / heading floor on live HTML
      if body.include?("<html") && !body.match?(/<title>[^<]+<\/title>|<h1\b/i)
        findings << soft("live page missing <title> and <h1>")
      end

      findings.each { |f| apply_finding(entry, f) }
      entry["http"] = code
      entry["ok"] = findings.none? { |f| f[:severity] == :hard }
      entry["findings"] = findings.map { |f| f[:message] }
      push_entry(entry)
    rescue StandardError => e
      entry["ok"] = false
      entry["findings"] = ["#{e.class}: #{e.message}"]
      @result.fail("page_sim live:#{page[:id]}: #{e.class}: #{e.message}")
      push_entry(entry)
    end

    # Source UX checks.

    def check_heading(page, body)
      return [] if page[:app] == "master" && page[:path].end_with?(".html")
      return [] if page[:view].include?("mailer")
      # Turbo fragment / embed shells are not full documents
      return [] if page[:action].to_s == "next" || page[:path].to_s.include?("widget")
      return [] if body.strip.start_with?("<turbo-frame") && !body.match?(/content_for/)

      has =
        body.match?(/content_for\s+:title/) ||
        body.match?(/<h1[\s>]/i) ||
        body.match?(/<h2[\s>]/i) || # city home intro uses h2 under layout title
        body.match?(/t\(["']pages\./) ||
        body.match?(/t\(["'][^"']*\.page_title/) ||
        body.match?(/t\(["']home\./) ||
        body.match?(/<!DOCTYPE html>/i) # full document templates (MASTER face)
      return [] if has

      [soft("#{page[:id]}: no content_for :title / h1 / pages.* title — weak page identity")]
    end

    def check_empty_cta(page, body)
      findings = []
      body.scan(/render\s*\(?\s*(?:partial:\s*)?["']shared\/empty_state["'](.*?)%>/m).each do |m|
        chunk = m[0].to_s
        next if chunk.include?("action:") || chunk.include?("actions:")
        # opt-out comment on preceding line is handled by empty_state_lint; soft here
        if body.include?("empty_state: no-action-ok")
          next
        end
        findings << soft("#{page[:id]}: empty_state without action: CTA (NO_DEAD_ENDS)")
      end
      findings
    end

    def check_dead_end(page, body)
      # Skip pure static public assets and mailers
      return [] if page[:path].to_s.end_with?(".html")
      return [] if body.strip.empty?
      return [] if page[:path].to_s.include?("widget")

      interactive =
        body.match?(/link_to|button_to|button_tag|submit_tag|form_with|form_for/) ||
        body.match?(/href=|type="submit"|data-action=/) ||
        body.match?(/render\s+["']shared\/empty_state/) ||
        body.match?(/turbo_frame|turbo-frame|data-controller/) ||
        body.match?(/live_search|search_field|text_field_tag|form_tag/)
      return [] if interactive

      # Very thin shells (turbo stream only) may still be OK
      return [soft("#{page[:id]}: no links/buttons/forms detected — possible dead end")] unless body.match?(/render\s+@|render\s+["']/)

      []
    end

    def check_auth_wall_source(page, body)
      return [] unless page[:persona] == "guest"
      return [] if page[:path].to_s.match?(AUTH_WALL_OK)

      if body.match?(/Sign in to continue/i) && !body.match?(/if\s+authenticated|unless\s+authenticated|signed_in/)
        return [hard("#{page[:id]}: hard-coded auth wall copy on guest surface")]
      end
      []
    end

    def check_form_labels(page, body)
      findings = []
      # Bare text_field without label helper nearby is a soft smell
      fields = body.scan(/\b(text_field|email_field|password_field|text_area|number_field|telephone_field)\b/).size
      labels = body.scan(/\blabel\b|aria-label|label_tag|f\.label/).size
      if fields.positive? && labels.zero?
        findings << soft("#{page[:id]}: #{fields} form field(s) with no label/aria-label in template")
      end
      findings
    end

    # Soft polish signal: visible CTA chrome still hardcoded in English.
    # Skips opt-outs and lines that already go through t(.
    HARDCODED_CTA = /
      (?:link_to|button_to)\s+
      "(?:Back to|Edit|Cancel|Open|Share|Wardrobe|Compose|More tools|All posts|Hot|Fresh|Top|Review|Reorder|Analytics|Like|Dressing room|Creator profile|All outfits|All style)[^"]*"
    /x

    def check_hardcoded_chrome(page, body)
      findings = []
      body.each_line.with_index(1) do |line, n|
        next if line.include?("t(") || line.include?("I18n.t")
        next if line.include?("chrome_i18n: ok")
        next unless line.match?(HARDCODED_CTA)

        findings << soft("#{page[:id]}:L#{n}: residual EN CTA chrome — use t(...)")
      end
      findings.first(5) # cap noise per page
    end

    def check_master_landmarks(page, body)
      return [] unless page[:app] == "master"
      return [] unless page[:path] == "/" || page[:path] == "/dashboard"

      findings = []
      if page[:path] == "/"
        findings << hard("#{page[:id]}: face missing id=face or primer") unless body.match?(/id=["']face["']|id=["']primer["']|id=["']zin["']/)
      end
      if page[:path] == "/dashboard"
        findings << hard("#{page[:id]}: mission control missing skip-link") unless body.match?(/skip-link|#main-content/)
        findings << hard("#{page[:id]}: mission control missing main landmark") unless body.match?(/id=["']main-content["']|role=["']main["']/)
      end
      findings
    end

    # Helpers.

    def base_entry(page)
      {
        "id" => page[:id],
        "app" => page[:app],
        "path" => page[:path],
        "host" => page[:host],
        "persona" => page[:persona],
        "view" => page[:view],
        "needs_id" => page[:needs_id],
      }
    end

    def push_entry(entry)
      @report["pages"] << entry
    end

    def hard(msg)
      { severity: :hard, message: msg }
    end

    def soft(msg)
      { severity: :soft, message: msg }
    end

    def apply_finding(entry, finding)
      label = "page_sim:#{entry['id']}"
      msg = finding[:message]
      full = msg.start_with?(entry["id"]) ? "page_sim:#{msg}" : "#{label}: #{msg}"
      @result.fail(full, severity: finding[:severity])
    end

    def soft_fail(entry, msg)
      apply_finding(entry, soft(msg))
      entry["ok"] = true
      entry["findings"] = [msg]
    end

    def fetch_with_host(url, host: nil, timeout: 12)
      uri = URI(url)
      Net::HTTP.start(uri.host, uri.port, open_timeout: 6, read_timeout: timeout) do |http|
        req = Net::HTTP::Get.new(uri.request_uri)
        req["Host"] = host if host
        req["Accept"] = "text/html"
        http.request(req)
      end
    end

    def write_report!(pages, ports_open, live_count)
      by_app = pages.group_by { |p| p[:app] }.transform_values(&:size)
      hard = @result.failures.size
      soft = @result.soft_failures.size
      @report["summary"] = {
        "total_pages" => pages.size,
        "by_app" => by_app,
        "guest" => pages.count { |p| p[:persona] == "guest" },
        "auth" => pages.count { |p| p[:persona] == "auth" },
        "live_probed" => live_count,
        "ports_open" => ports_open,
        "hard_findings" => hard,
        "soft_findings" => soft,
        "source_ok" => @report["pages"].count { |e| e["mode"] == "source" && e["ok"] },
        "source_total" => @report["pages"].count { |e| e["mode"] == "source" },
      }
      File.write(REPORT_PATH, @report.to_yaml)
      @result.warn("page_simulation: report → #{REPORT_PATH.sub("#{ROOT}/", "")}")
    end
  end
end
