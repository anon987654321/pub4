# frozen_string_literal: true

require "test_helper"

class NvdCveTest < ActiveSupport::TestCase
  setup do
    @platform = platforms(:openbsd)
    @category = Category.create!(platform: @platform, name: "nvd-test", slug: "nvd-test")
    @first = Port.create!(platform: @platform, category: @category, name: "alpha",
                          pkgpath: "security/alpha", version: "1")
    @second = Port.create!(platform: @platform, category: @category, name: "beta",
                           pkgpath: "security/beta", version: "1")
  end

  test "cross-reference uses the shared outbound guard and reports an empty success" do
    response = Net::HTTPOK.new("1.1", "200", "OK")
    response.instance_variable_set(:@read, true)
    response.instance_variable_set(:@body, JSON.generate("vulnerabilities" => []))
    request = nil

    Shared::OutboundHttp.stub(:request, lambda { |uri, **options|
      request = [ uri, options ]
      response
    }) do
      result = NvdCve.crossref(@first)
      assert_equal :succeeded, result.status
      assert_equal 0, result.count
    end

    uri, options = request
    assert_equal "https", uri.scheme
    assert_equal "services.nvd.nist.gov", uri.host
    assert_equal 5, URI.decode_www_form(uri.query).to_h.fetch("resultsPerPage").to_i
    assert_equal 5, options[:open_timeout]
    assert_equal 10, options[:read_timeout]
  end

  test "a failed NVD response is not reported as a successful empty result" do
    response = Net::HTTPServiceUnavailable.new("1.1", "503", "Unavailable")
    result = nil

    Shared::OutboundHttp.stub(:request, ->(_uri, **_options) { response }) do
      result = NvdCve.new(@first).crossref
    end

    assert_equal :failed, result.status
    assert_equal "IOError", result.error
  end

  test "one CVE discovered for two ports remains one advisory linked to both" do
    payload = {
      "id" => "CVE-2026-44002",
      "descriptions" => [{ "value" => "A sample vulnerability affecting multiple packages" }],
      "published" => "2026-09-01T12:00:00.000",
      "metrics" => { "cvssMetricV31" => [{ "cvssData" => { "baseScore" => 8.1 } }] }
    }

    first_record = NvdCve.new(@first).send(:record, payload)
    second_record = NvdCve.new(@second).send(:record, payload)

    assert_equal first_record.id, second_record.id
    assert_equal 1, SecurityAdvisory.where(identifier: "CVE-2026-44002").count
    assert_equal [ @first.id, @second.id ].sort, first_record.ports.pluck(:id).sort
  end
end
