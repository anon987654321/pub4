# frozen_string_literal: true

require "test_helper"

# DynamicHttp fetches a URL named in data/tools.dynamic.yml, which is a file an
# operator edits and, through DynamicTools::PATHS, one that can also come from
# ~/.master/tools.dynamic.yml. So the URL is data, and the thing standing between
# that data and a request to 169.254.169.254 is one line:
#
#     return Result.err(...) unless SsrfGuard.safe_uri?(uri)
#
# SsrfGuard itself has twelve tests. This class had none, so the guard was well
# covered and its only call site was not — reorder those two lines, or drop the
# `unless`, and every one of those twelve tests still passes.
#
# Nothing here opens a socket. Every case is refused before perform_request, which
# is the point: a test that needed the network could not prove a refusal.
class DynamicHttpTest < Minitest::Test
  # permit? returns a Result; err short-circuits the call.
  Governor = Struct.new(:answer) do
    def permit?(_name, _tier, _detail) = answer
  end

  def setup
    @governor = Governor.new(Master::Result.ok("permitted"))
    @http = Master::Io::DynamicHttp.new(governor: @governor)
  end

  def with_tool(defn)
    Master::Io::DynamicTools.stub(:lookup, defn) { yield }
  end

  def call(url, name: "probe", **extra)
    with_tool({ "name" => name, "url" => url, "elevated" => false }.merge(extra)) do
      @http.call(name: name, params: {})
    end
  end

  # Each row carries its own exposure, so two rows never share one verdict.
  def test_a_row_waits_for_elevation_unless_it_declares_otherwise
    @governor.answer = Master::Result.err("denied", category: :validation)

    waiting = with_tool({ "name" => "ping", "url" => "https://example.com/" }) { @http.call(name: "ping", params: {}) }
    open = call("https://example.com/", name: "status")

    assert_match(/waits for an elevated session/, waiting.message.to_s)
    assert_match(/denied/, open.message.to_s, "an unelevated row reaches the governor")
    Fiber[:master_elevated] = true
    elevated = with_tool({ "name" => "ping", "url" => "https://example.com/" }) { @http.call(name: "ping", params: {}) }
    assert_match(/denied/, elevated.message.to_s)
  ensure
    Fiber[:master_elevated] = nil
  end

  def test_an_unknown_tool_is_refused_before_anything_else
    result = with_tool(nil) { @http.call(name: "no-such-tool", params: {}) }

    refute result.ok?
    assert_match(/unknown tool/, result.message.to_s)
  end

  # The governor is asked before the URL is even parsed, so a denied call cannot
  # reach the network by way of a malformed address.
  def test_a_denied_governor_stops_the_call
    @governor.answer = Master::Result.err("denied", category: :validation)
    result = call("https://example.com/")

    refute result.ok?
    assert_match(/denied/, result.message.to_s)
  end

  def test_loopback_and_link_local_are_refused
    ["http://127.0.0.1/", "http://localhost/", "http://169.254.169.254/latest/meta-data/",
     "http://[::1]/", "http://10.0.0.1/", "http://192.168.1.1/"].each do |url|
      result = call(url)

      refute result.ok?, "#{url} must not be requested"
      assert_match(/refused internal|only http/, result.message.to_s, url)
    end
  end

  def test_non_http_schemes_are_refused
    ["file:///etc/passwd", "ftp://example.com/", "gopher://example.com/"].each do |url|
      result = call(url)

      refute result.ok?, "#{url} must not be requested"
      assert_match(/only http/, result.message.to_s, url)
    end
  end

  # A request that raises comes back as an infrastructure Err rather than
  # escaping into the tool loop. The guard and the request are stubbed, so no
  # socket opens.
  def test_a_failing_request_is_an_infrastructure_err
    Master::Io::SsrfGuard.stub(:safe_uri?, true) do
      @http.stub(:perform_request, ->(*) { raise Errno::ECONNREFUSED }) do
        result = call("https://example.com/")

        refute result.ok?
        assert_equal :infrastructure, result.category
        assert_match(/dynamic_http: .*refused/i, result.message.to_s)
      end
    end
  end

  # The URL is a template interpolated with caller-supplied params, so the guard
  # has to run on the interpolated result rather than on the template.
  def test_a_param_cannot_smuggle_an_internal_host_through_the_template
    with_tool({ "name" => "probe", "url" => "http://{host}/", "elevated" => false }) do
      result = @http.call(name: "probe", params: { host: "169.254.169.254" })

      refute result.ok?, "interpolation must be guarded, not just the template"
      assert_match(/refused internal/, result.message.to_s)
    end
  end

  def test_a_param_is_escaped_for_the_slot_it_fills
    defn = { "url" => "https://example.com/search?q={q}", "body_template" => %({"q":"{q}"}) }
    evil = %(x&admin=1"}, "role":"root)

    uri = @http.resolve_and_validate_uri(defn, { q: evil })
    assert_equal({ "q" => [evil] }, URI.decode_www_form(uri.query).group_by(&:first).transform_values { |v| v.map(&:last) })

    body = @http.send(:build_body, defn, { q: evil })
    assert_equal({ "q" => evil }, JSON.parse(body))
  end
end
