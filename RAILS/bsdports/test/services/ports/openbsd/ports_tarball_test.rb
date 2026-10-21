# frozen_string_literal: true

require "test_helper"
require "tmpdir"

class PortsTarballTest < ActiveSupport::TestCase
  setup do
    @tarball = Ports::Openbsd::PortsTarball.new(platform: platforms(:openbsd), release: "7.9")
  end

  test "an off-origin redirect is refused without a second request" do
    response = Net::HTTPFound.new("1.1", "302", "Found")
    response["location"] = "https://169.254.169.254/latest/meta-data"
    requests = 0

    Dir.mktmpdir do |dir|
      Shared::OutboundHttp.stub(:request, lambda { |_uri, **_options|
        requests += 1
        response
      }) do
        refute @tarball.send(:download, "https://cdn.openbsd.org/pub/OpenBSD/7.9/ports.tar.gz",
                             File.join(dir, "ports.tar.gz"))
      end
    end

    assert_equal 1, requests
  end

  test "plain HTTP and nonstandard ports never reach the outbound guard" do
    requests = 0
    Dir.mktmpdir do |dir|
      Shared::OutboundHttp.stub(:request, lambda { |_uri, **_options|
        requests += 1
        flunk "unsafe URLs must be rejected before an HTTP request"
      }) do
        refute @tarball.send(:download, "http://cdn.openbsd.org/ports.tar.gz", File.join(dir, "http.tar.gz"))
        refute @tarball.send(:download, "https://cdn.openbsd.org:8443/ports.tar.gz", File.join(dir, "port.tar.gz"))
      end
    end
    assert_equal 0, requests
  end

  test "release identifiers reject path and URL components" do
    invalid = Ports::Openbsd::PortsTarball.new(platform: platforms(:openbsd), release: "../internal")
    ENV["BSDPORTS_PORTS_TARBALL"] = "1"
    invalid.define_singleton_method(:verification_ready?) { true }
    assert_equal "invalid release identifier", invalid.decline_reason
  ensure
    ENV.delete("BSDPORTS_PORTS_TARBALL")
  end
end
