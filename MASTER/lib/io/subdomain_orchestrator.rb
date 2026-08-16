# frozen_string_literal: true

require "json"
require "net/http"
require "open3"
require "uri"

module Master
  module Io
    # Routes operator intent to pub4 subdomain clusters (brgen verticals, amber,
    # bsdports, MASTER). Maps the Gemini/Grok subdomain_orchestrator tool.
    class SubdomainOrchestrator
      TIER = :guarded
      NAME = "subdomain_orchestrator".freeze

      CLUSTER_DOMAINS = %w[
        marketplace playlist takeaway tv messages maps
        amber bsdports brgen ai dating messenger
      ].freeze

      # Named from the constant so the two cannot disagree: the model reads this to
      # decide whether the tool can serve a request, and `call` rejects anything
      # outside CLUSTER_DOMAINS. It used to list five of twelve and say "etc.".
      DESCRIPTION = "Synchronize or inspect a pub4 subdomain cluster " \
                    "(#{CLUSTER_DOMAINS.join(", ")}).".freeze

      APP_PORTS_PATH = File.join(Master::DEPLOY_ROOT, "deploy_inventory.json").freeze

      def initialize(root: Master::ROOT, event_bus: nil, web_fetch: nil)
        @root = root
        @bus = event_bus
        @web_fetch = web_fetch
      end

      def call(domain:, context: nil)
        key = normalize_domain(domain)
        return Result.err("subdomain_orchestrator: unknown domain #{domain}", category: :validation) unless CLUSTER_DOMAINS.include?(key)

        payload = route(key, context.to_s)
        @bus&.publish("subdomain:orchestrate", domain: key, ok: !payload.key?(:error))
        Result.ok(payload)
      rescue StandardError => e
        Result.err("subdomain_orchestrator: #{e.message}", category: :unknown)
      end

      def self.detect_intent(text)
        lowered = text.to_s.downcase
        CLUSTER_DOMAINS.find { |d| lowered.include?(d) }
      end

      private

      def normalize_domain(domain)
        d = domain.to_s.strip.downcase
        d = "marketplace" if d.start_with?("markedsplass", "markedsplads", "marktplatz", "marktplaats")
        d = "messages" if d == "messenger"
        d
      end

      def route(domain, context)
        case domain
        when "bsdports"
          probe_app("bsdports", "https://bsdports.org/up")
        when "maps"
          fetch_maps_viewport
        when "amber"
          probe_app(domain, app_url(domain))
        when "messages", "messenger"
          { broker: "active", cluster: "brgen", subdomain: "messenger", latency_ms: probe_latency("brgen"), queue_depth: 0 }
        when "marketplace", "takeaway", "playlist", "tv", "dating", "ai", "brgen"
          multi_tenant_status(domain, context)
        else
          { error: "Domain profile unallocated" }
        end
      end

      def multi_tenant_status(domain, context)
        {
          cluster: "rails-multi-tenant",
          subdomain: domain,
          host: "brgen.no",
          synchronized: probe_ok?("brgen"),
          timestamp: Time.now.to_i,
          context: context.strip.empty? ? nil : context.strip[0, 240],
        }.compact
      end

      def fetch_maps_viewport
        url = "https://maps.brgen.no/"
        if @web_fetch
          fetched = @web_fetch.call(url:)
          return { cluster: "maps", url:, fetch: fetched.ok? ? fetched.value![0, 800] : fetched.message } if fetched.ok?
        end
        probe = probe_http(url)
        { cluster: "maps", url:, status: probe[:status], synchronized: probe[:ok] }
      end

      def probe_app(name, url)
        probe = probe_http(url)
        return { error: "Upstream system verification delay", app: name, url: } unless probe[:ok]

        { status: "synchronized", app: name, url:, telemetry: probe[:body].to_s[0, 400] }
      end

      def app_url(name)
        entry = app_registry.find { |row| row["name"] == name }
        host = entry&.fetch("domain", nil).to_s.strip
        return if host.empty?

        "https://#{host}/up"
      end

      def probe_ok?(name)
        probe_http(app_url(name))[:ok]
      end

      def probe_latency(name)
        started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        probe_ok?(name)
        ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round
      rescue StandardError
        0
      end

      def probe_http(url, timeout: 4)
        return { ok: false, status: 0, body: "blocked" } if url.to_s.empty?

        uri = URI(url)
        return { ok: false, status: 0, body: "blocked" } unless SsrfGuard.safe_uri?(uri)

        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = uri.scheme == "https"
        http.open_timeout = timeout
        http.read_timeout = timeout
        res = http.get(uri.request_uri)
        body = res.body.to_s.strip
        { ok: res.code.to_i < 500, status: res.code.to_i, body: }
      rescue StandardError => e
        { ok: false, status: 0, body: e.message }
      end

      def app_registry
        return @app_registry if defined?(@app_registry) && @app_registry

        path = APP_PORTS_PATH
        raw = File.exist?(path) ? JSON.parse(File.read(path)) : {}
        @app_registry = Array(raw["apps"])
      rescue StandardError
        @app_registry = []
      end
    end
  end
end
