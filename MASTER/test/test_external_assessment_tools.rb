# frozen_string_literal: true

require_relative "test_helper"

class TestExternalAssessmentTools < Minitest::Test
  Governor = Struct.new(:answer, :asked) do
    def permit?(name, tier, detail)
      (self.asked ||= []) << [name, tier, detail]
      answer
    end
  end

  Response = Struct.new(:code, :body, :headers) do
    def each_header = headers.each
    def [](name) = headers[name.downcase]
  end

  def allow = Governor.new(Master::Result.ok("permitted"))
  def deny = Governor.new(Master::Result.err("denied", category: :policy))

  def test_external_audit_rejects_credentials_and_non_http_schemes
    tool = Master::Io::ExternalAudit.new(governor: allow)
    assert_equal :validation, tool.call(url: "https://user:pass@example.com").category
    assert_equal :validation, tool.call(url: "file:///etc/passwd").category
  end

  def test_external_audit_reports_header_and_html_observations
    tool = Master::Io::ExternalAudit.new(governor: allow)
    html = '<!doctype html><html lang="en"><head><title>Test</title><meta name="viewport" content="width=device-width"></head><body><main><h1>Hello</h1><img src="x.png"><img alt="" src="decor.png"><nav><a href="/">Home</a></nav></main></body></html>'
    response = Response.new("200", html, {
      "content-type" => "text/html; charset=utf-8",
      "strict-transport-security" => "max-age=31536000",
      "content-security-policy" => "default-src 'self'; frame-ancestors 'none'",
      "x-content-type-options" => "nosniff",
    })
    tool.define_singleton_method(:fetch_page) { |uri| [response, uri, 0] }

    result = tool.call(url: "https://example.com/")

    assert result.ok?, result.to_s
    assert_includes result.value!, "HTTP status: 200"
    assert_includes result.value!, "Content-Security-Policy: PRESENT"
    assert_includes result.value!, "HTML language: PRESENT (en)"
    assert_includes result.value!, "Images: 2 observed, 1 without alt attribute"
    assert_includes result.value!, "Framing protection: PRESENT via CSP"
  end

  def test_external_audit_does_not_fetch_when_governor_refuses
    tool = Master::Io::ExternalAudit.new(governor: deny)
    tool.define_singleton_method(:fetch_page) { |_uri| flunk("network request must not run") }
    assert_equal :policy, tool.call(url: "https://example.com/").category
  end

  def test_external_audit_refuses_localhost_without_connecting
    tool = Master::Io::ExternalAudit.new(governor: allow)
    result = tool.call(url: "http://localhost/")
    assert_equal :policy, result.category
    assert_match(/internal\/reserved/, result.message)
  end

  def test_vul_check_is_governed_before_local_probes
    tool = Master::Io::VulCheck.new(governor: deny)
    tool.define_singleton_method(:platform) { :linux }
    tool.define_singleton_method(:probe_line) { |*_args| flunk("probe must not run") }
    assert_equal :policy, tool.call.category
  end

  def test_vul_check_does_not_claim_unavailable_platform_was_clean
    tool = Master::Io::VulCheck.new(governor: allow)
    tool.define_singleton_method(:platform) { :unsupported }
    result = tool.call
    assert_equal :validation, result.category
    assert_match(/unsupported platform/, result.message)
  end

  def test_vul_check_without_scanner_flag_reports_scanners_not_run
    tool = Master::Io::VulCheck.new(governor: allow)
    tool.define_singleton_method(:platform) { :linux }
    tool.define_singleton_method(:posture_probes) { |_kind| [] }
    result = tool.call
    assert result.ok?, result.to_s
    assert_includes result.value!, "Optional scanners: NOT RUN"
    refute_includes result.value!, "COMPLETED"
  end

  def test_nmap_requires_authorization_before_target_resolution
    tool = Master::Io::Nmap.new(governor: allow)
    tool.define_singleton_method(:resolve_target) { |*_args, **_kwargs| flunk("target resolution must not run") }
    assert_equal :policy, tool.call(target: "example.com").category
  end

  def test_nmap_requires_governor_approval_before_scan
    tool = Master::Io::Nmap.new(governor: deny)
    tool.define_singleton_method(:resolve_target) { |_target, allow_private:| ["203.0.113.5", 4] }
    tool.define_singleton_method(:write_report) { |*_args| flunk("scan/report must not run") }
    assert_equal :policy, tool.call(target: "example.com", authorized: true).category
  end

  def test_nmap_rejects_cidr_and_port_syntax
    tool = Master::Io::Nmap.new(governor: allow)
    assert_equal :validation, tool.call(target: "192.0.2.0/24", authorized: true).category
    assert_equal :validation, tool.call(target: "example.com:443", authorized: true).category
  end

  def test_new_assessment_adapters_share_the_single_registry
    names = Master.load_yaml(File.join(Master::ROOT, "data", "tools.yml")).map { |row| row.fetch("name") }
    %w[ExternalAudit VulCheck Nmap].each do |name|
      assert_includes names, name
      assert Master::Builder::DEFAULT_TOOL_MAP.key?(name)
    end
    map = Master::Review::LLMDispatcher::LLM_TOOL_MAP
    assert_equal Master::Io::LLM::ExternalAudit, map.fetch(Master::Io::ExternalAudit)
    assert_equal Master::Io::LLM::VulCheck, map.fetch(Master::Io::VulCheck)
    assert_equal Master::Io::LLM::Nmap, map.fetch(Master::Io::Nmap)
  end
end
