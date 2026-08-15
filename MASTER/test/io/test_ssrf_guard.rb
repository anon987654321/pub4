# frozen_string_literal: true

require "test_helper"

# DEBT.md, Test coverage: no test named SsrfGuard. It is the only thing standing
# between a prompt-injection payload and the runtime's own internal network, and
# its whole contract is a list of ranges — the cheapest possible thing to get
# wrong silently and the cheapest possible thing to pin.
class SsrfGuardTest < Minitest::Test
  Guard = Master::Io::SsrfGuard

  def test_blocks_loopback_link_local_and_private
    %w[127.0.0.1 ::1 169.254.169.254 10.0.0.1 172.16.4.5 192.168.1.1 fe80::1].each do |address|
      assert Guard.blocked_ip?(IPAddr.new(address)), "#{address} must be blocked"
    end
  end

  def test_blocks_ipv4_mapped_loopback_and_metadata
    assert Guard.blocked_ip?(IPAddr.new("::ffff:127.0.0.1")), "mapped loopback must be blocked"
    assert Guard.blocked_ip?(IPAddr.new("::ffff:169.254.169.254")), "mapped metadata must be blocked"
  end

  # The cloud metadata endpoint is the reason this guard exists; keep it named.
  def test_blocks_the_cloud_metadata_address
    assert Guard.blocked_ip?(IPAddr.new("169.254.169.254"))
  end

  def test_blocks_the_declared_reserved_ranges
    Guard::RESERVED_RANGES.each do |range|
      assert Guard.blocked_ip?(range.to_range.first), "#{range} should be blocked at its first address"
    end
  end

  def test_allows_ordinary_public_addresses
    %w[1.1.1.1 93.184.216.34 2606:4700:4700::1111].each do |address|
      refute Guard.blocked_ip?(IPAddr.new(address)), "#{address} should be allowed"
    end
  end

  # An unparseable address must fail closed, not open.
  def test_an_unusable_argument_is_blocked
    assert Guard.blocked_ip?(Object.new)
  end

  def test_rejects_non_http_and_hostless_uris
    refute Guard.safe_uri?(URI.parse("file:///etc/passwd"))
    refute Guard.safe_uri?(URI.parse("ftp://example.com/x"))
    refute Guard.safe_uri?("http://example.com")
  end

  def test_rejects_localhost_by_name_without_resolving
    refute Guard.safe_uri?(URI.parse("http://localhost/admin"))
    refute Guard.safe_uri?(URI.parse("http://LOCALHOST:8080/admin"))
  end

  def test_rejects_a_hostname_that_resolves_to_a_private_address
    Resolv.stub(:getaddresses, ["10.1.2.3"]) do
      refute Guard.safe_uri?(URI.parse("http://internal.example.com/"))
    end
  end

  # A name with one public and one private answer is a rebinding-shaped input;
  # `all?` has to mean all.
  def test_rejects_a_mixed_answer_set
    Resolv.stub(:getaddresses, ["1.1.1.1", "127.0.0.1"]) do
      refute Guard.safe_uri?(URI.parse("http://mixed.example.com/"))
    end
  end

  def test_accepts_a_hostname_that_resolves_publicly
    Resolv.stub(:getaddresses, ["93.184.216.34"]) do
      assert Guard.safe_uri?(URI.parse("http://example.com/"))
    end
  end

  def test_rejects_a_name_that_does_not_resolve
    Resolv.stub(:getaddresses, []) do
      refute Guard.safe_uri?(URI.parse("http://nx.example.invalid/"))
    end
  end
end
