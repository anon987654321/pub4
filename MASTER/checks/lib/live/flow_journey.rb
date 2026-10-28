# frozen_string_literal: true

require "yaml"
require "net/http"
require "cgi"
require "uri"
require_relative "../../support/deploy_inventory"
require_relative "../../support/check_result"
require_relative "../../support/crawl_support"
require_relative "../../support/flow_coverage"
require_relative "../../support/fleet"

module Deploy
  # Journeys with postconditions on state, not a list of URLs with body regexes.
  #
  # The difference that matters: this follows redirects and knows where it
  # landed. A "guest-open" surface that 302s to /session/new and renders 200
  # from there passes a body-regex probe and fails here.
  class FlowJourneyCheck
    ROOT = File.expand_path("../../../..", __dir__)

    DATA = File.join(File.expand_path("../..", __dir__), "data", "flows.yml")
    MAX_REDIRECTS = 5
    # shared.flash.rate_limited, nb and en.
    RATE_LIMITED = /Prøv igjen senere|Try again later/

    def self.run = new.run

    def initialize(path: DATA, root: ROOT)
      @path = path
      @root = root
    end

    def run
      @result = CheckResult.new
      flows = Array(YAML.safe_load_file(@path)["flows"])
      # vps-deploy judges one app at a time: FLOW_APP=brgen runs only brgen's journeys,
      # so another app that is shed or mid-boot cannot fail this app's deploy.
      only = ENV["FLOW_APP"].to_s.split(",").map(&:strip).reject(&:empty?)

      flows = flows.select { |flow| only.include?(flow["app"]) } unless only.empty?
      ports = Inventory.new(root: @root).apps.to_h { |a| [a.name, a.port] }
      # FLOW_<APP>_PORT points one app's flows at a copy booted on a spare port.
      ports.each { |name, port| ports[name] = FlowCoverage.port_for(name, port) }

      counts = Hash.new(0)
      outcomes = Hash.new { |hash, key| hash[key] = {} }
      ran = 0
      flows.each do |flow|
        app = flow["app"]
        port = ports[app]
        unless port
          @result.fail("flow:#{flow["id"]} unknown app #{app.inspect}")
          @result.warn(surface_coverage_line(flow, app, :error, "unknown app"))

          counts[:error] += 1
          next
        end
        unless CrawlSupport.port_open?("127.0.0.1", port)
          @result.warn(surface_coverage_line(flow, app, :skipped, "skipped:app-down, port #{port} closed"))
          outcomes[app][flow["id"]] = :skipped
          counts[:skipped] += 1
          next
        end

        if flow["mutates"] && !FlowCoverage.writes_allowed?
          @result.inconclusive!(
            "flow:#{flow["id"]} did not run -- it writes accounts, posts or orders and this host serves production " \
            "(CHECK_ALLOW_WRITES=1 runs it against a throwaway copy of the app)",
          )

          @result.warn(surface_coverage_line(flow, app, :inconclusive, "writes refused on the deploy host"))
          outcomes[app][flow["id"]] = :inconclusive
          counts[:inconclusive] += 1
          next
        end

        state = run_flow(flow, port, app)
        outcomes[app][flow["id"]] = state == :skipped ? :inconclusive : state
        case state
        when :skipped
          # Missing credentials mean no request was made. Do not increment
          # checks_ran: that would turn an unmeasured account journey into green.
          counts[:inconclusive] += 1

          @result.warn(surface_coverage_line(flow, app, :inconclusive, "credentials unavailable"))
        when :failed
          ran += 1

          counts[:failed] += 1
          @result.checked!
          @result.warn(surface_coverage_line(flow, app, :fail))
        when :inconclusive
          # The guest flow ran, but its data invariant could not be evaluated.
          ran += 1

          counts[:inconclusive] += 1
          @result.checked!
          @result.warn(surface_coverage_line(flow, app, :inconclusive, "journey ran; invariant unmeasured"))
        else
          ran += 1
          counts[:passed] += 1
          @result.checked!

          @result.warn(surface_coverage_line(flow, app, :pass))
        end
      end
      outcomes.each do |app, states|
        @result.warn(FlowCoverage.summary_line("flow_journey", app, ports[app], states))
        down = states.select { |_id, state| state == :skipped }.keys
        next if down.empty?

        FlowCoverage.record_app_down(@result, check: "flow_journey", app:, port: ports[app], flows: down)
      end
      @result.warn(
        "flow_journey: ran #{ran}/#{flows.size}; pass=#{counts[:passed]} fail=#{counts[:failed]} " \
        "inconclusive=#{counts[:inconclusive]} skipped:app-down=#{counts[:skipped]} error=#{counts[:error]}",
      )
      @result
    end

    # A readable per-journey record. Host names make Brgen's verticals visible
    # in the same report as the city apex rather than disappearing inside app=brgen.
    def surface_coverage_line(flow, app, state, detail = nil)
      steps = Array(flow["steps"])
      surfaces = steps.group_by { |step| surface_host(step, app) }.map do |host, host_steps|
        paths = host_steps.map { |step| step["get"] || step["post"] || "(unknown path)" }.uniq
        host.empty? ? paths.join(", ") : "#{host} [#{paths.join(", ")}]"
      end

      description = "#{steps.size} step(s)"
      description += " — #{surfaces.join('; ')}" unless surfaces.empty?
      description += " — #{detail}" if detail && !detail.to_s.empty?
      "surface0: #{app}/#{flow["id"]} #{state.to_s.upcase} — #{description}"
    end

    def surface_host(step, app)
      explicit = step["host"].to_s.strip
      return explicit unless explicit.empty?

      Fleet.public_host(app).to_s
    rescue StandardError
      app.to_s
    end

    private

    # A journey that writes needs an account on the app under test, and this
    # check probes whatever database happens to be running. Hardcoding a login
    # would be a credential in git that works on one machine; inventing one
    # would need the check to write to a database it does not own. So the flow
    # names the environment it wants and is recorded unchecked without it, by
    # name, in the check's "Not checked" list.
    #
    # Unchecked is NOT blocking here, and measuring that live is what corrected
    # the first version of this comment. CHECK_STRICT_INCONCLUSIVE promotes only
    # `measured_nothing?` -- checks_ran zero -- so a run that exercises 25
    # journeys and skips one passes in either mode. check_result.rb says why in
    # as many words: promoting at record time made a check that ran fifty checks
    # and skipped one hard-fail on the deploy host. So the guarantee is narrower
    # than it looks and is worth stating plainly: the skipped journey is named
    # in the output every run and never counted as having passed, and noticing
    # it is still a person's job.
    def credentials_for(flow)
      keys = Array(flow["requires_credentials"])

      return {} if keys.empty?

      values = keys.to_h { |key| [ key, ENV[key].to_s ] }
      return values unless values.value?("")

      missing = values.select { |_, v| v.empty? }.keys
      @result.inconclusive!(
        "flow:#{flow["id"]} did not run — #{missing.join(', ')} unset, so the signed-in half " \
        "of this app went unmeasured (export them against a seeded app to run it)",
      )
      nil
    end

    def run_flow(flow, port, app)
      id = flow["id"]
      captures = {}
      failures_before = @result.failures.size
      unchecked_before = @result.unchecked.size
      client = FlowClient.new(port:, default_host: Fleet.public_host(app))
      credentials = credentials_for(flow)
      return :skipped if credentials.nil?

      # $unique is one token per flow run, so a sign-up or a post title can be
      # told apart from every earlier run's rows; strings a step captured join it.
      token = unique_token
      # The throwaway account a sign-up creates gets a password of its own for this run, so no
      # committed file carries one; flow_wrong_password is the same shape and never the right one.
      vars = credentials.merge("unique" => token, "flow_password" => "Passord-#{token}",
                               "flow_wrong_password" => "feil-passord-#{token}",
                               "flow_new_password" => "Nytt-passord-#{token}")

      Array(flow["steps"]).each do |step|
        name = step["name"] || step["get"] || step["post"]
        label = "flow:#{id}/#{name}"

        host = step["host"] || flow["host"]
        client.accept = step["accept"]
        # A value an optional capture could not find means the dataset has nothing
        # for this journey to act on: the app is unseeded, not broken.
        if (missing = Array(step["needs"]).reject { |key| vars.key?(key.to_s) }).any?
          @result.inconclusive!("#{label}: needs #{missing.join(', ')} from the page before it and found none -- the dataset is empty (seed the app)")

          return :inconclusive
        end
        if step["mail"]
          outcome = read_mail(label, step["mail"], app, vars)
          return outcome unless outcome == :read

          next
        end

        response = begin
          if (path = step["post"])
            client.post(interpolate(path, vars), resolve_params(step["params"], vars), host:)
          else
            client.get(interpolate(step.fetch("get"), vars), host:)
          end
        rescue StandardError => e
          @result.fail("#{label}: #{e.class}: #{e.message}")

          return :failed
        end

        return :failed unless check_step(label, step, response, captures, vars)
      end

      check_assertions(flow, captures)
      return :failed if @result.failures.size > failures_before
      return :inconclusive if @result.unchecked.size > unchecked_before

      :passed
    end

    # A journey over a catalogue cannot distinguish "search is broken" from
    # "nobody seeded this database" — and reporting the second as the first is
    # how a check loses its credibility. Flows that need rows say so, and an
    # empty dataset downgrades to a warning naming the cause.
    def unseeded?(flow, captures)
      return false unless flow["requires_data"]

      names = Array(flow["requires_data"]).map(&:to_s)
      names.all? { |n| captures[n].to_i.zero? }
    end

    # A step that opens a message the app sent, with no request of its own: the
    # development mailer writes tmp/mails/<recipient> (RAILS/__shared
    # development.rb), and the link inside is what a person would click. An app
    # that writes no file leaves the journey inconclusive, never failed -- it is
    # the environment that cannot be read, not the product that is wrong.
    def read_mail(label, spec, app, vars)
      dir = ENV["FLOW_#{app.upcase}_MAIL_DIR"] || File.join(@root, "RAILS", app, "tmp", "mails")

      path = File.join(dir, interpolate(spec.fetch("to"), vars))
      deadline = Time.now + spec.fetch("within", 10).to_f
      sleep 0.25 until File.file?(path) || Time.now > deadline
      unless File.file?(path)
        @result.inconclusive!("#{label}: no mail at #{path.sub("#{@root}/", '')} -- the app's mailer writes no file here, so the confirmation link went unfollowed")
        return :inconclusive
      end

      # The newest message in the file, and the first match in it: the plain-text
      # part comes before the HTML one, whose link can be re-encoded.
      text = mail_text(File.read(path).split(/^(?=Date: )/).last.to_s)
      Array(spec["capture"]).each do |capture|
        found = text.scan(Regexp.new(capture.fetch("pattern"))).flatten.first
        unless found
          @result.fail("#{label}: mail to #{spec["to"]} held nothing for #{capture["pattern"].inspect}")

          return :failed
        end
        vars[capture.fetch("as").to_s] = found
      end
      :read
    end

    # The file holds raw MIME. Quoted-printable would split a long link across
    # lines, and base64 would hide it; a 7bit part is left alone, because a
    # signed token may contain =XX that is not an escape. Quoted-printable is
    # decoded as bytes and read back as UTF-8: an escape decodes to a single
    # byte, and splicing that into a UTF-8 string holding "å" raises.
    def mail_text(raw)
      decoded = raw.gsub(/^([A-Za-z0-9+\/=]{40,})$/) { Regexp.last_match(1).unpack1("m").force_encoding(Encoding::UTF_8).scrub } if raw.match?(/Content-Transfer-Encoding: base64/i)
      decoded ||= raw
      return decoded.scrub unless raw.match?(/Content-Transfer-Encoding: quoted-printable/i)

      decoded.b.gsub(/=\r?\n/n, "").gsub(/=([0-9A-F]{2})/n) { Regexp.last_match(1).hex.chr }
             .force_encoding(Encoding::UTF_8).scrub
    end

    def unique_token = "#{Time.now.to_i.to_s(36)}#{rand(36**3).to_s(36)}"

    # `$name` takes the value a flow asked the environment for, a string an
    # earlier step captured, or $unique. Only names that exist are replaced, and
    # a value is inserted once and never rescanned, so a password containing a
    # dollar sign is a password and not a template.
    def interpolate(text, vars)
      text.to_s.gsub(/\$([A-Za-z_][A-Za-z0-9_]*)/) { vars.key?(Regexp.last_match(1)) ? vars[Regexp.last_match(1)] : Regexp.last_match(0) }
    end

    def resolve_params(params, vars)
      return params unless params.is_a?(Hash)

      params.to_h do |key, value|
        resolved = case value
                   when Hash then resolve_params(value, vars)
                   when String then interpolate(value, vars)
                   else value
                   end
        [interpolate(key, vars), resolved]
      end
    end

    def check_step(label, step, response, captures, vars = {})
      expected = Array(step["expect_status"]).map(&:to_i)
      expected = [200] if expected.empty?
      unless expected.include?(response.code)
        @result.fail("#{label}: HTTP #{response.code} (want #{expected.join('/')}) at #{response.final_url}")
        return false
      end

      if (want = step["expect_final_path"])
        actual = response.final_path
        hops = response.redirects.empty? ? "" : " via #{response.redirects.join(' → ')}"

        # `{ not: /session/new }` as well as a literal path. A successful sign-in
        # lands wherever the app was headed — root, the stored return path, a
        # vertical — so the only stable thing to assert is where it must NOT be.
        # Equality cannot say that, and without it a refused sign-in renders 200
        # from the sign-in page and every later step tests a guest while the
        # journey's name says account.
        want = interpolate(want, vars) if want.is_a?(String)

        if want.is_a?(Hash) && want.key?("matches")
          unless Regexp.new(interpolate(want["matches"], vars)).match?(actual)
            @result.fail("#{label}: landed on #{actual}#{hops}, not on a path matching #{want["matches"].inspect}")
            return false
          end
        elsif want.is_a?(Hash) && want.key?("not_matches")
          if Regexp.new(interpolate(want["not_matches"], vars)).match?(actual)
            @result.fail("#{label}: landed on #{actual}#{hops}, a path matching #{want["not_matches"].inspect} that this step must not reach")

            return false
          end
        elsif want.is_a?(Hash) && want.key?("not")
          if actual == want["not"]
            @result.fail("#{label}: landed back on #{actual}#{hops} — refused, not signed in")

            return false
          end
        elsif actual != want
          @result.fail("#{label}: landed on #{actual} not #{want}#{hops} — the surface redirected away")
          return false
        end
      end

      # Falcon/Net::HTTP may return BINARY; UTF-8 regexes need a compatible string.
      body = response.body.to_s.dup.force_encoding(Encoding::UTF_8)
      body = body.encode(Encoding::UTF_8, invalid: :replace, undef: :replace) unless body.valid_encoding?
      Array(step["expect_body"]).each do |pattern|
        pattern = interpolate(pattern, vars)
        next if Regexp.new(pattern).match?(body)

        @result.fail("#{label}: body missing #{pattern.inspect}")
      end

      any = Array(step["expect_any"]).map { |pattern| interpolate(pattern, vars) }
      if any.any? && any.none? { |pattern| Regexp.new(pattern).match?(body) }
        @result.fail("#{label}: body matched none of #{any.map(&:inspect).join(', ')}")
      end

      # The app's own rate limiter answers with a redirect and a flash, which looks
      # like success to a status check. Name it, or a rerun inside the window
      # reads as a product defect three steps later.
      if !step["asset"] && body.match?(RATE_LIMITED)
        @result.fail("#{label}: the app rate limited this request (\"try again later\") -- a rerun inside the limit window will fail here; wait it out or restart the app under test")
        return false
      end

      Array(step["forbid_body"]).each do |pattern|
        pattern = interpolate(pattern, vars)
        next unless Regexp.new(pattern).match?(body)

        @result.fail("#{label}: body contains forbidden #{pattern.inspect}", severity: :hard)
      end

      # asset: true marks a file rather than a page (a service worker is
      # JavaScript that says "Exception" legitimately), which an error-page
      # heuristic would misread.
      unless step["asset"]
        %w[Exception].each do |bad|
          @result.fail("#{label}: response contains #{bad}") if body.include?(bad)
        end
        @result.fail("#{label}: response contains Routing Error") if body.include?("Routing Error")
      end

      if (spec = step["count"])
        value = body.scan(Regexp.new(interpolate(spec.fetch("pattern"), vars))).size
        captures[spec.fetch("as").to_s] = value
      end
      vars[step["capture_final_path"].to_s] = response.final_path if step["capture_final_path"]
      capture_values(label, step, body, captures, vars)
    end

    # capture: the first group of a pattern, kept as a string for later steps
    # ($name in a path, a param or a pattern). number: the same, as an integer
    # an assertion can compare. A pattern that finds nothing fails the step: a
    # journey that carries on without the value would test a different page.
    def capture_values(label, step, body, captures, vars)
      ok = true

      %w[capture number].each do |kind|
        Array(step[kind]).each do |spec|
          match = Regexp.new(interpolate(spec.fetch("pattern"), vars)).match(body)
          next if match.nil? && spec["optional"]

          unless match && match[1]
            @result.fail("#{label}: #{kind} #{spec["as"].inspect} found nothing for #{spec["pattern"].inspect}")
            ok = false
            next
          end

          if kind == "number"
            captures[spec.fetch("as").to_s] = match[1].to_i
          else
            vars[spec.fetch("as").to_s] = CGI.unescapeHTML(match[1])
          end
        end
      end
      ok
    end

    OPS = {
      ">" => ->(a, b) { a > b }, "<" => ->(a, b) { a < b },
      ">=" => ->(a, b) { a >= b }, "<=" => ->(a, b) { a <= b },
      "==" => ->(a, b) { a == b }, "!=" => ->(a, b) { a != b }
    }.freeze

    def check_assertions(flow, captures)
      if unseeded?(flow, captures)
        # inconclusive!, not warn. Both print, but only unchecked is what
        # CHECK_STRICT_INCONCLUSIVE promotes to a failure, and "the invariants
        # did not run" is the definition of nothing measured. Filed as a warning
        # it was unpromotable in every mode, so a run that meant to demand a
        # seeded dataset had no way to say so and bsdports_search_narrows scored
        # green against an empty catalogue.
        @result.inconclusive!(
          "flow:#{flow["id"]} skipped invariants — #{Array(flow["requires_data"]).join('/')} is 0, " \
          "the dataset is empty (seed the app to make this journey meaningful)",
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
        right += rule["delta"].to_i if right && rule["delta"]
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
          "#{right_raw.is_a?(Integer) ? right : "#{right_raw}(#{right})"}#{why}",
        )
      end
    end

    # Cookie-jar HTTP client that follows redirects and remembers the path it
    # actually ended on.
    class FlowClient
      Response = Struct.new(:code, :body, :final_url, :redirects, keyword_init: true) do
        def final_path = URI(final_url).request_uri
      end

      # Rails puts the per-session token in a meta tag on every rendered page and
      # in a hidden field in every form. Either will do; the meta tag is on more
      # pages, so it is tried first.
      CSRF_META = /<meta name="csrf-token" content="([^"]+)"/
      CSRF_FIELD = /name="authenticity_token"[^>]*value="([^"]+)"/

      # default_host is the Host header every request carries unless a step names
      # its own. Without it a probe of the loopback identifies as nothing, and
      # production answers 403 from host authorization before the app sees the
      # path — so these journeys passed in development, where the allow list is
      # permissive, and could never pass against the deployed app, which is the
      # only place they measure anything.
      def initialize(port:, host: "127.0.0.1", default_host: nil)
        # One browser per journey. brgen's guest post quota is keyed on the user
        # agent, language and address and never resets, so journeys that all
        # presented as "Ruby" spent one shared allowance of 15 posts and every
        # later run was sent to the sign-in wall.
        @agent = "pub4-flow-journey/#{Time.now.to_i.to_s(36)}#{rand(36**4).to_s(36)}"

        @port = port
        @host = host
        @default_host = default_host
        @cookies = {}
        @csrf = nil
        @last_page = nil
      end

      # What this request asks for; nil is what a browser navigating sends. A step
      # naming a manifest or a JSON endpoint says so, as the browser fetching it would.
      attr_writer :accept

      def get(path, host: nil) = run(:get, path, nil, host)

      # A write, with the token the last rendered page handed us. Every journey
      # in flows.yml was a GET, so the signed-in half of the product — the
      # product — went unmeasured: a suite that only reads cannot tell a working
      # form from one that renders and drops what you type.
      def post(path, params, host: nil) = run(:post, path, params || {}, host)

      private

      def run(verb, path, params, host)
        redirects = []
        url = "http://#{@host}:#{@port}#{path}"
        header_host = host || @default_host
        MAX_REDIRECTS.times do
          response = request(url, header_host, verb, params)
          store_cookies(response)

          store_csrf(response.body)
          code = response.code.to_i
          if [301, 302, 303, 307, 308].include?(code)
            location = response["location"].to_s
            redirects << location
            url, header_host = follow(location, url, header_host)

            # 303 means "see other", and 301/302 after a POST are treated the
            # same way by every browser: the next hop is a GET with no body.
            # Replaying the params would post the form twice.
            verb, params = :get, nil if code != 307 && code != 308
            next
          end

          final = display_url(url, header_host)
          @last_page = final if verb == :get
          return Response.new(code:, body: response.body.to_s, final_url: final, redirects:)
        end
        raise "too many redirects (#{redirects.join(' → ')})"
      end

      def store_csrf(body)
        token = body.to_s[CSRF_META, 1] || body.to_s[CSRF_FIELD, 1]
        @csrf = token if token
      end

      # Where the next hop is fetched from, and under which name.
      #
      # Always the app under test: url stays on 127.0.0.1:<port> and the public
      # hostname travels in the Host header, which is the shape a relative
      # redirect already had. Taking an absolute Location at face
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

      def request(url, header_host, verb = :get, params = nil)
        uri = URI(url)
        Net::HTTP.start(uri.host, uri.port, open_timeout: 8, read_timeout: 15) do |http|
          req = build_request(uri, verb, params)
          req["Host"] = header_host if header_host

          # What a browser sends: HTML first, and the page the form sat on. Without
          # the first a content-negotiating route (search) answers JSON; without the
          # second redirect_back lands on its fallback and a "stay on the page"
          # action looks like a jump to the root.
          req["Accept"] = @accept || "text/html,application/xhtml+xml"

          req["User-Agent"] = @agent
          req["Referer"] = @last_page if @last_page && verb != :get
          req["Cookie"] = @cookies.map { |k, v| "#{k}=#{v}" }.join("; ") unless @cookies.empty?
          http.request(req)
        end
      end

      def build_request(uri, verb, params)
        return Net::HTTP::Get.new(uri.request_uri) if verb == :get

        req = Net::HTTP::Post.new(uri.request_uri)
        # The token goes in the header rather than the body: Rails accepts
        # either, and a header does not have to be threaded through nested
        # params whose shape differs per form.
        req["X-CSRF-Token"] = @csrf if @csrf
        req.set_form_data(flatten_params(params))
        req
      end

      # form_data is flat, and a Rails form is not: `{listing: {title: "x"}}`
      # has to arrive as `listing[title]=x`. One level of nesting is all any
      # journey here needs, and guessing deeper would hide a typo in a flow as
      # a silently dropped parameter.
      def flatten_params(params, prefix = nil)
        params.each_with_object({}) do |(key, value), out|
          name = prefix ? "#{prefix}[#{key}]" : key.to_s

          if value.is_a?(Hash)
            out.merge!(flatten_params(value, name))
          else
            out[name] = value.to_s
          end
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
