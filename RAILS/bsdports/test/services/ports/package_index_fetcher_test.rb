# frozen_string_literal: true

require "test_helper"

# `Location` is the mirror choosing our next request, and URI.join followed it
# to any host and scheme. A mirror that is hostile, hijacked or misconfigured
# could answer `Location: http://169.254.169.254/...` and this process would
# fetch it from inside the box. These pin the rule: a redirect may move the
# path, never the origin.
#
# Real Net::HTTPResponse subclasses, not stubs that answer is_a?. `case response
# when Net::HTTPRedirection` goes through Module#===, which asks the VM and not
# a Ruby-defined is_a? — so a struct pretending to be a redirect falls through
# to the else branch and returns nil. Three of these four then passed while
# measuring nothing, which is the shape they exist to catch in the code.
class PackageIndexFetcherRedirectTest < ActiveSupport::TestCase
  def redirect(location)
    Net::HTTPFound.new("1.1", "302", "Found").tap do |response|
      response["location"] = location
      response.instance_variable_set(:@read, true)
    end
  end

  def success(body)
    Net::HTTPOK.new("1.1", "200", "OK").tap do |response|
      response.instance_variable_set(:@read, true)
      response.instance_variable_set(:@body, body)
    end
  end

  def fetcher
    Ports::Openbsd::PackageIndexFetcher.new(platform: platforms(:openbsd),
                                            base: "https://cdn.openbsd.org/pub/OpenBSD")
  end

  # Records every host actually contacted, so a refused redirect is proved by
  # the request that never happened rather than by a nil that could come from
  # anywhere.
  def with(*responses)
    visited = []
    queue = responses.dup
    Net::HTTP.stub(:start, ->(host, *_args, **_opts) { visited << host; queue.shift }) do
      yield visited
    end
  end

  test "the stub is seen as a redirect at all" do
    assert_kind_of Net::HTTPRedirection, redirect("/x")
    assert_kind_of Net::HTTPSuccess, success("body")
  end

  test "a redirect within the mirror is followed" do
    with(redirect("/pub/OpenBSD/snapshots/INDEX"), success("INDEX BODY")) do |visited|
      assert_equal "INDEX BODY", fetcher.send(:get, "https://cdn.openbsd.org/pub/OpenBSD/INDEX")
      assert_equal %w[cdn.openbsd.org cdn.openbsd.org], visited
    end
  end

  test "a redirect to another host is refused and never fetched" do
    with(redirect("http://169.254.169.254/latest/meta-data/")) do |visited|
      assert_nil fetcher.send(:get, "https://cdn.openbsd.org/pub/OpenBSD/INDEX")
      assert_equal %w[cdn.openbsd.org], visited, "the metadata endpoint must never be contacted"
    end
  end

  test "a redirect that drops TLS on the same host is refused" do
    with(redirect("http://cdn.openbsd.org/pub/OpenBSD/INDEX")) do |visited|
      assert_nil fetcher.send(:get, "https://cdn.openbsd.org/pub/OpenBSD/INDEX")
      assert_equal %w[cdn.openbsd.org], visited
    end
  end

  test "an unusable Location is refused rather than raised" do
    with(redirect("http://[bad")) do |visited|
      assert_nil fetcher.send(:get, "https://cdn.openbsd.org/pub/OpenBSD/INDEX")
      assert_equal %w[cdn.openbsd.org], visited
    end
  end
end
