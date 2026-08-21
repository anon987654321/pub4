# frozen_string_literal: true

require "net/http"
require "uri"
require_relative "../../../../OPENBSD/lib/deploy_inventory"
require_relative "../../../../OPENBSD/lib/gate_result"
require_relative "../../../tools/crawl_support"
require_relative "../../support/dom_surface_schema"

module Deploy
  # Live + fixture DOM surface schemas (home, marketplace, dating, messenger).
  class SurfaceSchemaGate
    ROOT = File.expand_path("../../../..", __dir__)
    FIXTURES = File.join(File.expand_path("../..", __dir__), "fixtures", "surfaces")

    # schema_id => { app, path, host }
    LIVE_SURFACES = [
      { schema: "brgen_home", app: "brgen", path: "/", host: "brgen.no" },
      # live_feed went with the Jodel surface. /live is a redirect to the geo
      # room now, so there is no page here to hold to a schema of its own.
      { schema: "marketplace_listings", app: "brgen", path: "/", host: "markedsplass.brgen.no" },
      { schema: "marketplace_cart", app: "brgen", path: "/cart", host: "markedsplass.brgen.no" },
      { schema: "dating_home", app: "brgen", path: "/", host: "dating.brgen.no" },
      { schema: "messenger_inbox", app: "brgen", path: "/conversations", host: "brgen.no" },
    ].freeze

    def self.run
      new.run
    end

    def run
      @result = GateResult.new
      @schema = DomSurfaceSchema.new
      run_fixtures
      run_live
      @result
    end

    private

    def run_fixtures
      unless File.directory?(FIXTURES)
        @result.warn("surface_schema: no fixtures dir #{FIXTURES}")
        return
      end

      # Good fixtures must pass; bad fixtures must produce ≥1 finding.
      Dir.glob(File.join(FIXTURES, "good_*.html")).each do |path|
        id = File.basename(path, ".html").sub(/\Agood_/, "")
        html = File.read(path)
        findings = @schema.check(html, id)
        findings.each { |f| @result.fail("fixture good/#{id}: #{f.message}", severity: f.severity) }
      end

      Dir.glob(File.join(FIXTURES, "bad_*.html")).each do |path|
        id = File.basename(path, ".html").sub(/\Abad_/, "")
        html = File.read(path)
        findings = @schema.check(html, id)
        if findings.empty?
          @result.fail("fixture bad/#{id}: expected schema findings, got none (gate blind)")
        else
          @result.warn("surface_schema fixture bad/#{id}: correctly caught #{findings.size} issue(s)")
        end
      end
    end

    def run_live
      inventory = Inventory.new(root: ROOT).apps.to_h { |a| [a.name, a] }
      LIVE_SURFACES.each do |surface|
        app = inventory[surface[:app]]
        unless app
          @result.fail("surface_schema: unknown app #{surface[:app]}")
          next
        end
        unless CrawlSupport.port_open?("127.0.0.1", app.port)
          @result.skipped_live("surface_schema: #{surface[:schema]} skipped (port #{app.port} closed)")
          next
        end

        url = "http://127.0.0.1:#{app.port}#{surface[:path]}"
        body = fetch(url, host: surface[:host])
        if body.nil?
          @result.fail("surface_schema: #{surface[:schema]} fetch failed")
          next
        end
        @schema.apply_to_result!(@result, body, surface[:schema])
      end
    end

    def fetch(url, host: nil)
      uri = URI(url)
      res = Net::HTTP.start(uri.host, uri.port, open_timeout: 8, read_timeout: 15) do |http|
        req = Net::HTTP::Get.new(uri.request_uri)
        req["Host"] = host if host
        http.request(req)
      end
      code = res.code.to_i
      return nil unless code.between?(200, 399)

      res.body.to_s
    rescue StandardError # scan: intentional — nil is the measured-nothing signal, reported downstream as the gate's warning
      nil
    end
  end
end
