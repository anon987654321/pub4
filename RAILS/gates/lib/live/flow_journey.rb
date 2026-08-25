# frozen_string_literal: true

require "yaml"
require "net/http"
require "uri"
require_relative "../../../../OPENBSD/lib/deploy_inventory"
require_relative "../../../../OPENBSD/lib/gate_result"
require_relative "../../../tools/crawl_support"

module Deploy
  # Journeys with postconditions on state, not a list of URLs with body regexes.
  #
  # The difference that matters: this follows redirects and knows where it
  # landed. A "guest-open" surface that 302s to /session/new and renders 200
  # from there passes a body-regex probe and fails here.
  class FlowJourneyGate
    ROOT = File.expand_path("../../../..", __dir__)
    DATA = File.join(File.expand_path("../..", __dir__), "data", "flows.yml")
    MAX_REDIRECTS = 5

    def self.run = new.run

    def initialize(path: DATA, root: ROOT)
      @path = path
      @root = root
    end

    def run
      @result = GateResult.new
      flows = Array(YAML.safe_load_file(@path)["flows"])
      ports = Inventory.new(root: @root).apps.to_h { |a| [a.name, a.port] }
      # MASTER web is not a RAILS/apps.yml row — face + mission control.
      ports["master"] ||= 53187

      ran = 0
      flows.each do |flow|
        app = flow["app"]
        port = ports[app]
        unless port
          @result.fail("flow:#{flow["id"]} unknown app #{app.inspect}")
          next
        end
        unless CrawlSupport.port_open?("127.0.0.1", port)
          @result.skipped_live("flow:#{flow["id"]} skipped — #{app} port #{port} closed")
          next
        end
        ran += 1
        run_flow(flow, port)
      end
      @result.warn("flow_journey: ran #{ran}/#{flows.size} journeys") if ran.positive?
      @result
    end

    private

    def run_flow(flow, port)
      id = flow["id"]
      captures = {}
      client = FlowClient.new(port: port)

      Array(flow["steps"]).each do |step|
        name = step["name"] || step["get"]
        label = "flow:#{id}/#{name}"
        response = begin
          client.get(step.fetch("get"), host: step["host"])
        rescue StandardError => e
          @result.fail("#{label}: #{e.class}: #{e.message}")
          return
        end

        return unless check_step(label, step, response, captures)
      end

      check_assertions(flow, captures)
    end

    # A journey over a catalogue cannot distinguish "search is broken" from
    # "nobody seeded this database" — and reporting the second as the first is
    # how a gate loses its credibility. Flows that need rows say so, and an
    # empty dataset downgrades to a warning naming the cause.
    def unseeded?(flow, captures)
      return false unless flow["requires_data"]

      names = Array(flow["requires_data"]).map(&:to_s)
      names.all? { |n| captures[n].to_i.zero? }
    end

    def check_step(label, step, response, captures)
      expected = Array(step["expect_status"]).map(&:to_i)
      expected = [200] if expected.empty?
      unless expected.include?(response.code)
        @result.fail("#{label}: HTTP #{response.code} (want #{expected.join('/')}) at #{response.final_url}")
        return false
      end

      if (want = step["expect_final_path"])
        actual = response.final_path
        unless actual == want
          hops = response.redirects.empty? ? "" : " via #{response.redirects.join(' → ')}"
          @result.fail("#{label}: landed on #{actual} not #{want}#{hops} — the surface redirected away")
          return false
        end
      end

      # Falcon/Net::HTTP may return BINARY; UTF-8 regexes need a compatible string.
      body = response.body.to_s.dup.force_encoding(Encoding::UTF_8)
      body = body.encode(Encoding::UTF_8, invalid: :replace, undef: :replace) unless body.valid_encoding?
      Array(step["expect_body"]).each do |pattern|
        next if Regexp.new(pattern).match?(body)

        @result.fail("#{label}: body missing #{pattern.inspect}")
      end

      any = Array(step["expect_any"])
      if any.any? && any.none? { |pattern| Regexp.new(pattern).match?(body) }
        @result.fail("#{label}: body matched none of #{any.map(&:inspect).join(', ')}")
      end

      Array(step["forbid_body"]).each do |pattern|
        next unless Regexp.new(pattern).match?(body)

        @result.fail("#{label}: body contains forbidden #{pattern.inspect}", severity: :hard)
      end

      %w[Exception].each do |bad|
        @result.fail("#{label}: response contains #{bad}") if body.include?(bad)
      end
      @result.fail("#{label}: response contains Routing Error") if body.include?("Routing Error")

      if (spec = step["count"])
        value = body.scan(Regexp.new(spec.fetch("pattern"))).size
        captures[spec.fetch("as").to_s] = value
      end
      true
    end

    OPS = {
      ">" => ->(a, b) { a > b }, "<" => ->(a, b) { a < b },
      ">=" => ->(a, b) { a >= b }, "<=" => ->(a, b) { a <= b },
      "==" => ->(a, b) { a == b }, "!=" => ->(a, b) { a != b },
    }.freeze

    def check_assertions(flow, captures)
      if unseeded?(flow, captures)
        @result.warn(
          "flow:#{flow["id"]} skipped invariants — #{Array(flow["requires_data"]).join('/')} is 0, " \
          "the dataset is empty (seed the app to make this journey meaningful)"
        )
        return
      end

      Array(flow["assert"]).each do |rule|
        left_name = rule.fetch("left").to_s
        unless captures.key?(left_name)
          @result.fail("flow:#{flow["id"]} assertion references unknown capture #{left_name.inspect}")
          next
        end
        left = captures.fetch(left_name)
        right_raw = rule.fetch("right")
        right = right_raw.is_a?(Integer) ? right_raw : captures[right_raw.to_s]
        if right.nil?
          @result.fail("flow:#{flow["id"]} assertion references unknown capture #{right_raw.inspect}")
          next
        end

        op = OPS[rule.fetch("op").to_s]
        unless op
          @result.fail("flow:#{flow["id"]} unknown operator #{rule["op"].inspect}")
          next
        end
        next if op.call(left, right)

        why = rule["why"] ? " — #{rule["why"]}" : ""
        @result.fail(
          "flow:#{flow["id"]} invariant broken: #{left_name}(#{left}) #{rule["op"]} " \
          "#{right_raw.is_a?(Integer) ? right : "#{right_raw}(#{right})"}#{why}"
        )
      end
    end

    # Cookie-jar HTTP client that follows redirects and remembers the path it
    # actually ended on.
    class FlowClient
      Response = Struct.new(:code, :body, :final_url, :redirects, keyword_init: true) do
        def final_path = URI(final_url).request_uri
      end

      def initialize(port:, host: "127.0.0.1")
        @port = port
        @host = host
        @cookies = {}
      end

      def get(path, host: nil)
        redirects = []
        url = "http://#{@host}:#{@port}#{path}"
        header_host = host
        MAX_REDIRECTS.times do
          response = request(url, header_host)
          store_cookies(response)
          code = response.code.to_i
          if [301, 302, 303, 307, 308].include?(code)
            location = response["location"].to_s
            redirects << location
            url, header_host = follow(location, url, header_host)
            next
          end
          return Response.new(code: code, body: response.body.to_s,
                              final_url: display_url(url, header_host), redirects: redirects)
        end
        raise "too many redirects (#{redirects.join(' → ')})"
      end

      private

      # Where the next hop is fetched from, and under which name.
      #
      # Always the app under test: url stays on 127.0.0.1:<port> and the public
      # hostname travels in the Host header, which is the shape a relative
      # redirect already had. An absolute Location used to be taken at face
      # value, so a 301 to http://brgen.no/nearby/room sent the next request to
      # the real brgen.no on port 80 — relayd answers there with a TLS redirect
      # that Net::HTTP reads as "EOFError: end of file reached", which is how
      # this was found. The quiet half is the worse one: every absolute redirect
      # that did not happen to fail was measuring production and reporting it as
      # a local journey.
      def follow(location, current, header_host)
        target = URI.join(current, location)
        host = local?(target.host) ? header_host : target.host

        [ "http://#{@host}:#{@port}#{target.request_uri}", host ]
      end

      def local?(host) = [ @host, "127.0.0.1", "localhost" ].include?(host)

      # Report the vanity host in messages when one was used, so a failure reads
      # markedsplass.brgen.no/cart rather than 127.0.0.1:38182/cart.
      def display_url(url, header_host)
        return url unless header_host

        uri = URI(url)
        "http://#{header_host}#{uri.request_uri}"
      end

      def request(url, header_host)
        uri = URI(url)
        Net::HTTP.start(uri.host, uri.port, open_timeout: 8, read_timeout: 15) do |http|
          req = Net::HTTP::Get.new(uri.request_uri)
          req["Host"] = header_host if header_host
          req["Cookie"] = @cookies.map { |k, v| "#{k}=#{v}" }.join("; ") unless @cookies.empty?
          http.request(req)
        end
      end

      def store_cookies(response)
        Array(response.get_fields("Set-Cookie")).each do |raw|
          key, value = raw.split(";").first.to_s.split("=", 2)
          @cookies[key] = value if key && value
        end
      end
    end
  end
end
