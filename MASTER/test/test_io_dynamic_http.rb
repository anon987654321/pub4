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
    with_tool({ "name" => name, "url" => url }.merge(extra)) do
      @http.call(name: name, params: {})
    end
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

  # The URL is a template interpolated with caller-supplied params, so the guard
  # has to run on the interpolated result rather than on the template.
  def test_a_param_cannot_smuggle_an_internal_host_through_the_template
    with_tool({ "name" => "probe", "url" => "http://{host}/" }) do
      result = @http.call(name: "probe", params: { host: "169.254.169.254" })

      refute result.ok?, "interpolation must be guarded, not just the template"
      assert_match(/refused internal/, result.message.to_s)
    end
  end
end
