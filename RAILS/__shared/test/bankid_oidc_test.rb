# frozen_string_literal: true

require "base64"
require "digest"
require "jwt"
require "minitest/autorun"
require "minitest/mock"
require "openssl"
require_relative "../lib/omniauth/bankid_oidc"

class BankidOIDCTest < Minitest::Test
  OIDC = Shared::BankidOIDC
  ISSUER = "https://auth.current.bankid.no/auth/realms/current"
  CLIENT_ID = "bankid-test-client"
  NONCE = "test-nonce-value"

  def setup
    @now = Time.now.to_i
    @root_key, @root = build_certificate(ca: true)
    @leaf_key, @leaf = build_certificate(ca: false, issuer: @root, issuer_key: @root_key)
    @jwk = JWT::JWK.new(@leaf_key, { kid: "test-signing-key" }).export.transform_keys(&:to_s)
    @jwk["alg"] = "ES256"
    @jwk["use"] = "sig"
    @jwk["x5c"] = [@leaf, @root].map { |certificate| Base64.strict_encode64(certificate.to_der) }
    @discovery = {
      "issuer" => ISSUER,
      "authorization_endpoint" => "#{ISSUER}/precheck/auth",
      "token_endpoint" => "#{ISSUER}/protocol/openid-connect/token",
      "jwks_uri" => "#{ISSUER}/protocol/openid-connect/certs"
    }
  end

  def test_verifies_signature_certificate_chain_nonce_and_required_claims
    token = signed_token
    fingerprint = Digest::SHA256.hexdigest(@root.to_der)
    OIDC.stub(:trusted_root_fingerprint, fingerprint) do
      claims = OIDC.verify_id_token!(
        token, environment: "current", client_id: CLIENT_ID, nonce: NONCE,
        discovery: @discovery, jwks: { "keys" => [@jwk] }, now: @now
      )
      assert_equal "person-subject", claims.fetch("sub")
      assert_equal "urn:bankid:bid;LOA=4", claims.fetch("acr")
    end
  end

  def test_rejects_acr_values_that_do_not_claim_high_assurance
    fingerprint = Digest::SHA256.hexdigest(@root.to_der)
    ["urn:bankid:bid", "4", "urn:bankid:bid;LOA=3"].each do |acr|
      OIDC.stub(:trusted_root_fingerprint, fingerprint) do
        assert_raises(OIDC::InvalidToken, "accepted #{acr}") do
          OIDC.verify_id_token!(
            signed_token("acr" => acr), environment: "current", client_id: CLIENT_ID, nonce: NONCE,
            discovery: @discovery, jwks: { "keys" => [@jwk] }, now: @now
          )
        end
      end
    end
  end

  def test_rejects_wrong_nonce_after_valid_signature
    fingerprint = Digest::SHA256.hexdigest(@root.to_der)
    OIDC.stub(:trusted_root_fingerprint, fingerprint) do
      assert_raises(OIDC::InvalidToken) do
        OIDC.verify_id_token!(
          signed_token, environment: "current", client_id: CLIENT_ID, nonce: "wrong",
          discovery: @discovery, jwks: { "keys" => [@jwk] }, now: @now
        )
      end
    end
  end

  def test_rejects_wrong_audience
    fingerprint = Digest::SHA256.hexdigest(@root.to_der)
    OIDC.stub(:trusted_root_fingerprint, fingerprint) do
      assert_raises(OIDC::InvalidToken) do
        OIDC.verify_id_token!(
          signed_token, environment: "current", client_id: "different-client", nonce: NONCE,
          discovery: @discovery, jwks: { "keys" => [@jwk] }, now: @now
        )
      end
    end
  end

  def test_rejects_a_signing_chain_with_an_unpublished_root
    assert_raises(OIDC::InvalidToken) do
      OIDC.verify_id_token!(
        signed_token, environment: "current", client_id: CLIENT_ID, nonce: NONCE,
        discovery: @discovery, jwks: { "keys" => [@jwk] }, now: @now
      )
    end
  end

  def test_refuses_unknown_environment_and_non_bankid_hosts
    assert_raises(OIDC::InvalidToken) { OIDC.configuration("staging") }
    assert_raises(OIDC::InvalidToken) do
      OIDC.send(:validate_endpoint!, "https://attacker.example/.well-known/openid-configuration", "current")
    end
  end

  private

  def signed_token(overrides = {})
    payload = {
      "iss" => ISSUER,
      "aud" => CLIENT_ID,
      "sub" => "person-subject",
      "iat" => @now - 10,
      "exp" => @now + 300,
      "nonce" => NONCE,
      "acr" => "urn:bankid:bid;LOA=4",
      "name" => "Test Person"
    }.merge(overrides)
    JWT.encode(payload, @leaf_key, "ES256", { "kid" => "test-signing-key" })
  end

  def build_certificate(ca:, issuer: nil, issuer_key: nil)
    key = OpenSSL::PKey::EC.generate("prime256v1")
    certificate = OpenSSL::X509::Certificate.new
    certificate.version = 2
    certificate.serial = rand(1..(2**30))
    certificate.subject = OpenSSL::X509::Name.parse(ca ? "/CN=BankID Test Root" : "/CN=BankID Test Signer")
    issuer ||= certificate
    issuer_key ||= key
    certificate.issuer = issuer.subject
    certificate.public_key = key
    certificate.not_before = Time.now - 60
    certificate.not_after = Time.now + 3600

    extensions = OpenSSL::X509::ExtensionFactory.new
    extensions.subject_certificate = certificate
    extensions.issuer_certificate = issuer
    extensions.create_extension("basicConstraints", ca ? "CA:TRUE" : "CA:FALSE", true).then { |ext| certificate.add_extension(ext) }
    extensions.create_extension("keyUsage", ca ? "keyCertSign, cRLSign" : "digitalSignature", true).then { |ext| certificate.add_extension(ext) }
    certificate.add_extension(extensions.create_extension("subjectKeyIdentifier", "hash", false))
    certificate.add_extension(extensions.create_extension("authorityKeyIdentifier", "keyid:always", false))
    certificate.sign(issuer_key, OpenSSL::Digest::SHA256.new)
    [key, certificate]
  end
end
