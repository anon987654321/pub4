# frozen_string_literal: true

require "test_helper"

class SharedScrapeTest < ActiveSupport::TestCase
  PUBLIC_ADDRESS = "8.8.8.8"

  def public_resolver
    ->(_host) { [PUBLIC_ADDRESS] }
  end

  test "scrape entrypoints accept only public HTTP and HTTPS targets" do
    assert Shared::Scrape.public_http_url?("https://example.com/page", resolver: public_resolver)
    assert Shared::Scrape.public_http_url?("http://reddit.com/r/bergen", resolver: public_resolver)

    [
      "file:///etc/passwd",
      "ftp://example.com/file",
      "https://user:secret@example.com/",
      "http://localhost/admin",
      "http://127.0.0.1/admin",
      "http://169.254.169.254/latest/meta-data",
      "http://192.168.1.10/",
      "http://[::1]/admin",
    ].each do |url|
      refute Shared::Scrape.public_http_url?(url, resolver: public_resolver), url
    end
  end

  test "DNS names are rejected if any answer is private or reserved" do
    mixed = ->(_host) { [PUBLIC_ADDRESS, "10.12.0.4"] }
    private_only = ->(_host) { ["127.0.0.1"] }
    empty = ->(_host) { [] }

    refute Shared::Scrape.public_http_url?("https://mixed.example/", resolver: mixed)
    refute Shared::Scrape.public_http_url?("https://private.example/", resolver: private_only)
    refute Shared::Scrape.public_http_url?("https://missing.example/", resolver: empty)
    assert Shared::Scrape.public_http_url?("https://public.example/", resolver: public_resolver)
  end

  test "browser requests and redirects are checked by the same target policy" do
    resolver = ->(_host) { [PUBLIC_ADDRESS] }

    assert Shared::Scrape.safe_request_url?("https://example.com/image.png", resolver:)
    assert Shared::Scrape.safe_request_url?("data:image/png;base64,AA==", resolver:)
    refute Shared::Scrape.safe_request_url?("http://127.0.0.1/latest/meta-data", resolver:)
    refute Shared::Scrape.safe_request_url?("file:///etc/passwd", resolver:)

    source = File.read(Rails.root.join("../__shared/app/services/shared/scrape.rb"), encoding: "UTF-8")
    assert_includes source, "browser.network.intercept"
    assert_includes source, "browser.on(:request)"
    assert_includes source, "safe_request_url?(request.url)"
  end
end
