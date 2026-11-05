# frozen_string_literal: true

require "test_helper"

class SharedScrapeTest < ActiveSupport::TestCase
  PUBLIC_ADDRESS = "8.8.8.8"

  def public_resolver
    ->(_host) { [ PUBLIC_ADDRESS ] }
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
      "http://[::1]/admin"
    ].each do |url|
      refute Shared::Scrape.public_http_url?(url, resolver: public_resolver), url
    end
  end

  test "DNS names are rejected if any answer is private or reserved" do
    mixed = ->(_host) { [ PUBLIC_ADDRESS, "10.12.0.4" ] }
    private_only = ->(_host) { [ "127.0.0.1" ] }
    empty = ->(_host) { [] }

    refute Shared::Scrape.public_http_url?("https://mixed.example/", resolver: mixed)
    refute Shared::Scrape.public_http_url?("https://private.example/", resolver: private_only)
    refute Shared::Scrape.public_http_url?("https://missing.example/", resolver: empty)
    assert Shared::Scrape.public_http_url?("https://public.example/", resolver: public_resolver)
  end

  test "browser requests and redirects are checked by the same target policy" do
    resolver = ->(_host) { [ PUBLIC_ADDRESS ] }

    assert Shared::Scrape.safe_request_url?("https://example.com/image.png", resolver:)
    assert Shared::Scrape.safe_request_url?("data:image/png;base64,AA==", resolver:)
    refute Shared::Scrape.safe_request_url?("http://127.0.0.1/latest/meta-data", resolver:)
    refute Shared::Scrape.safe_request_url?("file:///etc/passwd", resolver:)

    source = File.read(Rails.root.join("../__shared/app/services/shared/scrape.rb"), encoding: "UTF-8")
    assert_includes source, "browser.network.intercept"
    assert_includes source, "browser.on(:request)"
    assert_includes source, "safe_request_url?(request.url)"
    refute_match(/browser_options:\s*\{[^}]*no-sandbox/m, source,
                 "untrusted pages must not run outside Chromium's sandbox")
  end

  test "IPv4 and IPv6 special-purpose ranges never become scrape destinations" do
    blocked = %w[
      0.0.0.0
      100.64.0.1
      192.0.2.1
      198.18.0.1
      224.0.0.1
      240.0.0.1
      ::
      ::1
      ::ffff:7f00:1
      64:ff9b:1::1
      100::1
      2001:db8::1
      fc00::1
      fe80::1
      ff02::1
    ]

    blocked.each do |address|
      host = address.include?(":") ? "[#{address}]" : address
      refute Shared::Scrape.public_http_url?("https://#{host}/"), address
    end
  end

  test "IPv4-embedded NAT64 and 6to4 addresses inherit the embedded address policy" do
    {
      "64:ff9b::a9fe:a9fe" => false,
      "64:ff9b::a00:1" => false,
      "64:ff9b::808:808" => true,
      "2002:a9fe:a9fe::1" => false,
      "2002:0a00:0001::1" => false,
      "2002:0808:0808::1" => true
    }.each do |address, expected|
      actual = Shared::Scrape.public_http_url?("https://[#{address}]/")
      assert_equal expected, actual, address
    end
  end

  test "localhost suffixes remain blocked after DNS normalization" do
    %w[localhost. service.local service.internal printer.home.arpa].each do |host|
      refute Shared::Scrape.public_http_url?("http://#{host}/", resolver: public_resolver), host
    end
  end
end
