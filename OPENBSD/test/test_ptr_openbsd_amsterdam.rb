# frozen_string_literal: true

require "minitest/autorun"
require "json"
require_relative "../ptr_openbsd_amsterdam"

# Setting a PTR record changes how the internet names this box, and the script
# is run perhaps once a year. The dry run is what an operator reads before
# APPLY_PTR=1, so it must describe the exact request and must not send it.
class PtrOpenbsdAmsterdamTest < Minitest::Test
  def dry_run(ip:, hostname:)
    ptr = Operator::PtrOpenbsdAmsterdam.new(ip:, hostname:, apply: false)
    sent = []
    result = nil
    original = Net::HTTP.method(:start)
    Net::HTTP.define_singleton_method(:start) { |*args, **| sent << args }
    out, = capture_io { result = ptr.call }
    [ptr, JSON.parse(out), result, sent.any?]
  ensure
    Net::HTTP.define_singleton_method(:start, original)
  end

  def test_a_dry_run_builds_the_post_and_sends_nothing
    ptr, report, result, sent = dry_run(ip: "46.23.89.226", hostname: "ns.brgen.no")

    refute sent, "a dry run reached the network"
    assert result
    assert_equal({ "dry_run" => true, "endpoint" => "http://ptr4.openbsd.amsterdam",
                   "ip" => "46.23.89.226", "hostname" => "ns.brgen.no", "method" => "POST" },
                 report.except("note"))
    uri = ptr.send(:build_request).uri
    assert_equal "ip=46.23.89.226&hostname=ns.brgen.no", uri.query
  end

  def test_an_ipv6_address_goes_to_the_ipv6_endpoint
    _, report, = dry_run(ip: "2a03:6000:1:1::226", hostname: "ns.brgen.no")

    assert_equal "http://ptr6.openbsd.amsterdam", report.fetch("endpoint")
  end

  def test_bad_input_is_refused_before_a_request_exists
    [["127.0.0.1", "ns.brgen.no"], ["46.23.89.226", "ns"], ["not an ip", "ns.brgen.no"]].each do |ip, hostname|
      assert_raises(ArgumentError, "#{ip} #{hostname} was accepted") do
        Operator::PtrOpenbsdAmsterdam.new(ip:, hostname:).call
      end
    end
  end
end
