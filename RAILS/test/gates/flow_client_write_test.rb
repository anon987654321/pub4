# frozen_string_literal: true

require "minitest/autorun"
require "socket"
require_relative "../../gates/lib/live/flow_journey"

# Every journey in flows.yml was a GET: 55 steps, 55 of them reads, and not one
# flow declaring an actor. So the gate proved 23 journeys do not 500 for a
# stranger and could prove nothing about the signed-in half of the product —
# which is the product. A suite that only reads cannot tell a working form from
# one that renders and quietly drops what you type.
#
# These are the pieces a write needs, tested without a server because that is
# where the mistakes are: a token read off the wrong page, a nested param
# flattened wrong, a credential placeholder that eats a real password.
class FlowClientWriteTest < Minitest::Test
  def setup
    @client = Deploy::FlowJourneyGate::FlowClient.new(port: 38_182)
    @gate = Deploy::FlowJourneyGate.new
  end

  def flatten(params) = @client.send(:flatten_params, params)
  def store_csrf(body) = @client.send(:store_csrf, body)
  def csrf = @client.instance_variable_get(:@csrf)

  def test_a_nested_param_arrives_in_rails_bracket_form
    assert_equal({ "listing[title]" => "Ski", "listing[price_cents]" => "900" },
                 flatten(listing: { title: "Ski", price_cents: 900 }))
  end

  def test_a_flat_param_is_left_alone
    assert_equal({ "email_address" => "a@b.no" }, flatten(email_address: "a@b.no"))
  end

  def test_the_token_is_read_from_the_meta_tag
    store_csrf(%(<meta name="csrf-token" content="abc123">))

    assert_equal "abc123", csrf
  end

  # Rails renders the meta tag on pages and the hidden field inside forms. A
  # client that knew only one of them would work on whichever page the first
  # journey happened to fetch and fail on the next.
  def test_the_token_is_read_from_a_hidden_form_field
    store_csrf(%(<input type="hidden" name="authenticity_token" value="xyz789" />))

    assert_equal "xyz789", csrf
  end

  def test_a_page_without_a_token_leaves_the_last_one_standing
    store_csrf(%(<meta name="csrf-token" content="first">))
    store_csrf("<p>a turbo stream carries no meta tag</p>")

    assert_equal "first", csrf
  end

  def test_a_post_carries_the_token_in_a_header_and_the_params_in_the_body
    store_csrf(%(<meta name="csrf-token" content="tok">))
    req = @client.send(:build_request, URI("http://127.0.0.1:38182/session"), :post,
                       { email_address: "a@b.no", password: "s3cret" })

    assert_equal "tok", req["X-CSRF-Token"]
    assert_includes req.body, "email_address=a%40b.no"
    assert_includes req.body, "password=s3cret"
  end

  def test_a_get_carries_no_body_and_no_token
    req = @client.send(:build_request, URI("http://127.0.0.1:38182/"), :get, nil)

    assert_instance_of Net::HTTP::Get, req
    assert_nil req["X-CSRF-Token"]
  end

  def test_a_credential_placeholder_is_substituted
    resolved = @gate.send(:resolve_params, { "user" => { "password" => "$FLOW_PASSWORD" } },
                          { "FLOW_PASSWORD" => "hunter2" })

    assert_equal({ "user" => { "password" => "hunter2" } }, resolved)
  end

  # A password may begin with a dollar sign, and swallowing it as an unset
  # placeholder would sign in as nobody and report the form broken.
  def test_a_dollar_sign_that_names_no_credential_stays_a_literal
    resolved = @gate.send(:resolve_params, { "password" => "$ecret" }, { "FLOW_PASSWORD" => "x" })

    assert_equal({ "password" => "$ecret" }, resolved)
  end

  # Without credentials the flow is unchecked rather than passed. That is
  # weaker than it first reads and the live run is what showed it:
  # GATE_STRICT_INCONCLUSIVE promotes only a gate that measured *nothing*,
  # so a run that skips this one journey and passes 25 others still passes.
  # What unchecked buys is that the journey is named in the output every
  # run and never counted among the passes.
  def test_a_flow_missing_its_credentials_is_unchecked_not_passed
    @gate.instance_variable_set(:@result, Deploy::GateResult.new)
    flow = { "id" => "signed_in_write", "requires_credentials" => %w[FLOW_NOT_SET_ANYWHERE] }

    assert_nil @gate.send(:credentials_for, flow)
    result = @gate.instance_variable_get(:@result)
    assert_equal 1, result.unchecked.size
    assert_includes result.unchecked.first, "FLOW_NOT_SET_ANYWHERE"
    assert_empty result.failures, "a missing credential is not a verdict about the tree"
  end

  def test_a_flow_with_no_credential_requirement_runs_as_before
    @gate.instance_variable_set(:@result, Deploy::GateResult.new)

    assert_equal({}, @gate.send(:credentials_for, { "id" => "guest_journey" }))
  end

  # A successful sign-in lands wherever the app was headed, so the only stable
  # assertion is where it must NOT be. Without the negation a refused sign-in
  # renders 200 from the sign-in page and every later step in the journey tests
  # a guest under a name that says account.
  def test_expect_final_path_can_assert_where_a_step_must_not_land
    @gate.instance_variable_set(:@result, Deploy::GateResult.new)
    response = Deploy::FlowJourneyGate::FlowClient::Response.new(
      code: 200, body: "", final_url: "http://brgen.no/session/new", redirects: []
    )
    step = { "expect_status" => [ 200 ], "expect_final_path" => { "not" => "/session/new" } }

    refute @gate.send(:check_step, "flow:x/sign_in", step, response, {})
    assert_includes @gate.instance_variable_get(:@result).failures.first, "refused, not signed in"
  end

  def test_expect_final_path_negation_passes_when_the_step_landed_elsewhere
    @gate.instance_variable_set(:@result, Deploy::GateResult.new)
    response = Deploy::FlowJourneyGate::FlowClient::Response.new(
      code: 200, body: "", final_url: "http://brgen.no/", redirects: []
    )
    step = { "expect_status" => [ 200 ], "expect_final_path" => { "not" => "/session/new" } }

    assert @gate.send(:check_step, "flow:x/sign_in", step, response, {})
    assert_empty @gate.instance_variable_get(:@result).failures
  end
end

# The one thing the unit cases above cannot reach: a POST over a real socket,
# through the redirect, carrying the session cookie the sign-in set. stdlib
# TCPServer rather than a web framework, for the same reason the rendered
# gates drive CDP by hand — these run under bare `ruby` outside any bundle.
class FlowClientOverASocketTest < Minitest::Test
  # Sign-in form -> POST /session (303) -> /items, which is only reachable
  # with the cookie the POST handed back.
  def serve(server)
    Thread.new do
      3.times do
        socket = server.accept
        request = socket.gets.to_s
        headers = {}
        while (line = socket.gets) && line != "\r\n"
          k, v = line.split(":", 2)
          headers[k.to_s.downcase] = v.to_s.strip
        end
        verb, target, = request.split
        body = ""
        if verb == "POST"
          body = socket.read(headers["content-length"].to_i)
          @posted = { body: body, csrf: headers["x-csrf-token"] }
        end

        socket.print(response_for(verb, target, headers))
        socket.close
      end
    rescue StandardError
      nil
    end
  end

  def response_for(verb, target, headers)
    if verb == "GET" && target == "/session/new"
      page = %(<meta name="csrf-token" content="TOKEN-1">)
      "HTTP/1.1 200 OK\r\nContent-Length: #{page.bytesize}\r\n\r\n#{page}"
    elsif verb == "POST" && target == "/session"
      "HTTP/1.1 303 See Other\r\nLocation: /items\r\n" \
        "Set-Cookie: session_id=abc; path=/\r\nContent-Length: 0\r\n\r\n"
elsif verb == "POST"
  # The hop after a 303 must be a GET. Replaying the body posts the form a
  # second time, which is a duplicate record rather than an error -- the
  # kind of bug a gate that only reads can never see.
  page = "<h1>the form was posted twice</h1>"
  "HTTP/1.1 200 OK\r\nContent-Length: #{page.bytesize}\r\n\r\n#{page}"
    elsif headers["cookie"].to_s.include?("session_id=abc")
      page = "<h1>your items</h1>"
      "HTTP/1.1 200 OK\r\nContent-Length: #{page.bytesize}\r\n\r\n#{page}"
    else
      "HTTP/1.1 302 Found\r\nLocation: /session/new\r\nContent-Length: 0\r\n\r\n"
    end
  end

  def test_a_sign_in_post_follows_its_redirect_and_carries_the_session
    server = TCPServer.new("127.0.0.1", 0)
    thread = serve(server)
    client = Deploy::FlowJourneyGate::FlowClient.new(port: server.addr[1])

    client.get("/session/new")
    response = client.post("/session", { email_address: "a@b.no", password: "s3cret" })

    assert_equal 200, response.code, "the POST must follow its 303 and land signed in"
    assert_equal "/items", response.final_path
    assert_includes response.body, "your items"
      refute_includes response.body, "posted twice", "the hop after a 303 must be a GET"
    assert_equal "TOKEN-1", @posted[:csrf], "the token from the form page must travel with the POST"
    assert_includes @posted[:body], "password=s3cret"
  ensure
    thread&.kill
    server&.close
  end
end
