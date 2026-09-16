# frozen_string_literal: true

require "net/http"
require "uri"
require "cgi"
require_relative "../../../OPENBSD/lib/gate_result"

module Deploy
  # Guest-open HTTP persona: cookie jar, optional location, capability asserts.
  # Craigslist-style apps must pass these without signup walls.
  class GuestFlowPersona
    CAPABILITIES = {
      no_auth_wall: {
        principle: "clarity / guest_open",
        fail_if: /Sign in to continue/i,
        severity: :hard,
      },
      has_main: {
        principle: "accessibility",
        require: /#main-content|<main\b|skip-link|Skip to main/i,
        severity: :hard,
      },
      messenger_compose: {
        principle: "good_design_is_useful",
        require: /messenger-compose|Messages|Start chat|New message/i,
        severity: :hard,
      },
      marketplace_browse: {
        principle: "catalog_retail",
        require: /navBar|deal-grid|deal-card|Markedsplass|listings/i,
        severity: :hard,
      },
      marketplace_cart: {
        principle: "good_design_is_useful",
        require: /Cart|Your Cart/i,
        severity: :hard,
      },
      dating_browse: {
        principle: "face",
        require: /Oppdag|swipe|dating|profile/i,
        severity: :hard,
      },
    }.freeze

    # path/host probes for brgen guest-open core
    BRGEN_PROBES = [
      { label: "home", path: "/", host: "brgen.no", capabilities: %i[no_auth_wall has_main] },
      # /live folded into /nearby/room in 76612fd0b — two hyperlocal surfaces
      # where one already contained the other. It is a redirect now, so probing
      # it for live-feed markup asserted against a page that no longer renders.
      { label: "messenger", path: "/conversations", host: "brgen.no", capabilities: %i[no_auth_wall has_main messenger_compose] },
      { label: "messenger_host", path: "/", host: "messenger.brgen.no", capabilities: %i[no_auth_wall messenger_compose] },
      { label: "marketplace", path: "/", host: "markedsplass.brgen.no", capabilities: %i[no_auth_wall marketplace_browse] },
      { label: "marketplace_cart", path: "/cart", host: "markedsplass.brgen.no", capabilities: %i[no_auth_wall marketplace_cart] },
      { label: "marketplace_sell", path: "/listings/new", host: "markedsplass.brgen.no", capabilities: %i[no_auth_wall] },
      { label: "dating", path: "/", host: "dating.brgen.no", capabilities: %i[no_auth_wall dating_browse] },
    ].freeze

    attr_reader :cookies, :base_host, :port

    def initialize(port:, base_host: "127.0.0.1")
      @port = port
      @base_host = base_host
      @cookies = {}
    end

    def get(path, host: nil)
      request(:get, path, host: host)
    end

    def patch_location(lat:, lng:, host: nil)
      request(:patch, "/location", host: host, form: { "latitude" => lat, "longitude" => lng })
    end

    def assert_capabilities(body, *caps, label:)
      findings = []
      caps.flatten.each do |cap|
        spec = CAPABILITIES[cap.to_sym]
        raise ArgumentError, "unknown capability #{cap}" unless spec

        if spec[:fail_if] && body.match?(spec[:fail_if])
          findings << {
            severity: spec[:severity] || :hard,
            message: "guest_flow:#{label} capability #{cap} hit auth wall (#{spec[:principle]})",
          }
        end
        if spec[:require] && !body.match?(spec[:require])
          findings << {
            severity: spec[:severity] || :hard,
            message: "guest_flow:#{label} capability #{cap} missing #{spec[:require].inspect} (#{spec[:principle]})",
          }
        end
      end
      findings
    end

    def run_brgen_probes!(result, port_open:)
      unless port_open
        result.skipped_live("guest_flow: brgen port closed — guest capability probes skipped")
        return result
      end

      BRGEN_PROBES.each do |probe|
        res = get(probe[:path], host: probe[:host])
        code = res[:code].to_i
        unless code.between?(200, 399)
          result.fail("guest_flow:#{probe[:label]} HTTP #{code} Host=#{probe[:host]}#{probe[:path]}", severity: :hard)
          next
        end
        body = res[:body].to_s
        %w[Exception Routing Error].each do |bad|
          # "Routing Error" as two words in page
          next if bad == "Routing"
        end
        if body.include?("Exception") || body.include?("Routing Error")
          result.fail("guest_flow:#{probe[:label]} saw exception body", severity: :hard)
        end
        assert_capabilities(body, *probe[:capabilities], label: probe[:label]).each do |f|
          result.fail(f[:message], severity: f[:severity])
        end
      end
      result
    end

    private

    def request(method, path, host: nil, form: nil)
      uri = URI("http://#{@base_host}:#{@port}#{path}")
      Net::HTTP.start(uri.host, uri.port, open_timeout: 8, read_timeout: 15) do |http|
        req =
          case method
          when :get then Net::HTTP::Get.new(uri.request_uri)
          when :patch then Net::HTTP::Patch.new(uri.request_uri)
          when :post then Net::HTTP::Post.new(uri.request_uri)
          else raise ArgumentError, method.to_s
          end
        req["Host"] = host if host
        req["Cookie"] = cookie_header unless @cookies.empty?
        if form
          req["Content-Type"] = "application/x-www-form-urlencoded"
          req["X-CSRF-Token"] = @csrf if @csrf
          req.body = URI.encode_www_form(form)
        end
        res = http.request(req)
        store_cookies(res)
        body = res.body.to_s
        if (m = body.match(/name="csrf-token"\s+content="([^"]+)"/))
          @csrf = m[1]
        end
        { code: res.code, body: body, headers: res.to_hash }
      end
    end

    def store_cookies(res)
      Array(res.get_fields("Set-Cookie")).each do |raw|
        pair = raw.split(";").first
        k, v = pair.split("=", 2)
        @cookies[k] = v if k && v
      end
    end

    def cookie_header
      @cookies.map { |k, v| "#{k}=#{v}" }.join("; ")
    end
  end
end
