# frozen_string_literal: true

require "minitest/autorun"
require "openssl"
require_relative "../bin/domain_watch"

# The offline half of `domain_watch.rb --tls`: which hosts it probes and how it
# decides a certificate covers one. The network half is run by hand on the day.
class TestDomainWatchTls < Minitest::Test
  def certificate(*names)
    key = OpenSSL::PKey::EC.generate("prime256v1")
    cert = OpenSSL::X509::Certificate.new
    cert.version = 2
    cert.serial = 1
    cert.subject = cert.issuer = OpenSSL::X509::Name.parse("/CN=#{names.first}")
    cert.public_key = key
    cert.not_before = Time.now - 60
    cert.not_after = Time.now + 86_400
    ext = OpenSSL::X509::ExtensionFactory.new(cert, cert)
    cert.add_extension(ext.create_extension("subjectAltName", names.map { |n| "DNS:#{n}" }.join(",")))
    cert.sign(key, OpenSSL::Digest.new("SHA256"))
    cert
  end

  def test_every_relayd_keypair_is_probed_with_the_brgen_verticals
    hosts = Deploy::DomainWatch.tls_hosts
    File.read(Deploy::DomainWatch::RELAYD_CONF, encoding: "UTF-8").scan(/tls keypair "([^"]+)"/).flatten.each do |name|
      assert_includes hosts, name
    end
    assert_includes hosts, "markedsplass.brgen.no"
    assert_equal hosts.uniq, hosts
  end

  def test_a_certificate_covers_its_names_and_one_wildcard_label_only
    cert = certificate("brgen.no", "tv.brgen.no", "*.example.org")

    assert Deploy::DomainWatch.covers?(cert, "tv.brgen.no")
    assert Deploy::DomainWatch.covers?(cert, "www.example.org")
    refute Deploy::DomainWatch.covers?(cert, "dating.brgen.no"), "a name absent from the SANs must not pass"
    refute Deploy::DomainWatch.covers?(cert, "a.b.example.org"), "a wildcard spans one label"
  end
end
