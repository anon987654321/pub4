# frozen_string_literal: true

require_relative "test_helper"
require "yaml"

class TestWebBrowse < Minitest::Test
  Router = Master::Ground::EvidenceRouter
  Guard = Master::Io::SsrfGuard

  class Governor
    def permit?(*) = Master::Result.ok(true)
  end

  class InterceptedRequest
    attr_reader :url, :method, :headers, :response_options
    attr_accessor :aborted, :continued

    def initialize(url:, method: "GET", headers: {})
      @url = url
      @method = method
      @headers = headers
    end

    def abort = (@aborted = true)
    def continue = (@continued = true)
    def respond(**options) = (@response_options = options)
  end

  class FakeResponse
    attr_reader :code

    def initialize(code: "200", headers: { "content-type" => "text/plain" }, body: "hello")
      @code = code
      @headers = headers.transform_keys(&:downcase)
      @body = body
    end

    def each_header(&block) = @headers.each(&block)
    def get_fields(name)
      value = @headers[name.downcase]
      value.nil? ? nil : Array(value)
    end
    def [](name) = @headers[name.downcase]
    def read_body
      yield(@body) unless @body.empty?
    end
  end

  class FakeHTTP
    attr_reader :last_request

    def initialize(response)
      @response = response
    end

    def start
      yield self
    end

    def request(request)
      @last_request = request
      yield @response
      @response
    end

    def started? = false
  end

  def tool = Master::Io::WebBrowse.new(governor: Governor.new)

  def test_it_refuses_internal_and_non_http_addresses_before_starting_a_browser
    %w[http://127.0.0.1/ http://169.254.169.254/latest/meta-data/ http://localhost:3000/].each do |url|
      assert tool.call(url:).err?, "#{url} must be refused"
    end
    assert tool.call(url: "file:///etc/passwd").err?
    assert tool.call(url: "https://user:pass@example.com/").err?
  end

  def test_browser_disables_direct_networking_and_keeps_native_sandbox
    options = tool.class::BROWSER_OPTIONS
    refute options.key?("no-sandbox")
    assert_equal "MAP * ~NOTFOUND", options.fetch("host-resolver-rules")
    assert options.key?("disable-quic")
    assert_includes tool.class::NETWORK_SANDBOX_SCRIPT, "WebSocket"
    assert_includes tool.class::NETWORK_SANDBOX_SCRIPT, "RTCPeerConnection"
  end

  def test_subrequest_is_fetched_at_the_checked_ip_and_fulfilled
    request = InterceptedRequest.new(url: "https://example.com/a.js", headers: { "User-Agent" => "Chrome", "Authorization" => "must-not-forward" })
    response = FakeResponse.new(headers: { "content-type" => "application/javascript", "content-length" => "5" }, body: "hello")
    client = FakeHTTP.new(response)
    addresses = []

    Guard.stub(:pinned_address, ->(uri) { uri.host == "example.com" ? "93.184.216.34" : nil }) do
      Guard.stub(:http_for, ->(_uri, address, timeout:) { addresses << [address, timeout]; client }) do
        tool.send(:handle_request, request, budget: tool.send(:new_budget))
      end
    end

    assert_equal [["93.184.216.34", Master::Io::WebBrowse::REQUEST_TIMEOUT]], addresses
    assert_equal "hello", request.response_options[:body]
    assert_equal 200, request.response_options[:responseCode]
    refute request.continued, "Chrome must not connect directly"
    refute request.aborted
    refute client.last_request.key?("authorization")
    assert_equal "identity", client.last_request["accept-encoding"]
  end

  def test_upstream_content_encoding_is_preserved
    request = InterceptedRequest.new(url: "https://example.com/compressed.js")
    response = FakeResponse.new(
      headers: { "content-type" => "application/javascript", "content-encoding" => "gzip" },
      body: "compressed-wire-bytes",
    )
    client = FakeHTTP.new(response)

    Guard.stub(:pinned_address, "93.184.216.34") do
      Guard.stub(:http_for, ->(_uri, _address, timeout:) { client }) do
        tool.send(:handle_request, request, budget: tool.send(:new_budget))
      end
    end

    assert_equal "gzip", request.response_options[:responseHeaders]["content-encoding"]
    assert_equal "compressed-wire-bytes", request.response_options[:body]
  end

  def test_non_http_subrequests_are_aborted
    request = InterceptedRequest.new(url: "file:///etc/passwd")

    tool.send(:handle_request, request, budget: tool.send(:new_budget))

    assert request.aborted
    refute request.response_options
  end

  def test_mutating_http_methods_are_aborted
    request = InterceptedRequest.new(url: "https://example.com/cart", method: "POST")

    tool.send(:handle_request, request, budget: tool.send(:new_budget))

    assert request.aborted
  end

  def test_redirect_to_a_local_file_is_fulfilled_as_forbidden_not_followed
    request = InterceptedRequest.new(url: "https://example.com/start")
    response = FakeResponse.new(code: "302", headers: { "location" => "file:///etc/passwd" }, body: "")
    client = FakeHTTP.new(response)

    Guard.stub(:pinned_address, "93.184.216.34") do
      Guard.stub(:http_for, ->(_uri, _address, timeout:) { client }) do
        tool.send(:handle_request, request, budget: tool.send(:new_budget))
      end
    end

    assert_equal 403, request.response_options[:responseCode]
    assert_includes request.response_options[:body], "Blocked unsafe redirect"
  end

  def test_it_is_registered_for_the_builder_the_llm_and_the_catalogue
    assert Master::Builder::DEFAULT_TOOL_MAP.key?("WebBrowse")
    assert_equal Master::Io::LLM::WebBrowse, Master::Review::LLMDispatcher::LLM_TOOL_MAP.fetch(Master::Io::WebBrowse)
    names = YAML.safe_load_file(File.join(Master::ROOT, "data", "tools.yml")).map { |row| row["name"] }
    assert_includes names, "WebBrowse"
  end

  def test_a_request_naming_a_site_routes_to_the_browser
    assert_equal :browser, Router.classify("hi, can you find me a decent movie wall projector at temu.com?")
    assert_equal :browser, Router.classify("check https://www.kjell.com/no/sok?query=projektor for cheap ones")
  end

  def test_file_names_are_still_repository_questions
    assert_equal :repository, Router.classify("what is in lib/fix/fix_loop.rb")
    assert_equal :repository, Router.classify("open notes.md and summarise it")
  end

  def test_the_browser_prompt_names_the_tool_and_forbids_giving_up_untried
    prompt = Router.prompt_for(:browser)
    assert_includes prompt, "WebBrowse"
    assert_includes prompt, "Try WebBrowse before saying a site cannot be read"
  end
end
