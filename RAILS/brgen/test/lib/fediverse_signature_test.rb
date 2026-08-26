# frozen_string_literal: true

require "test_helper"

# The security boundary of the whole feature. An inbox that verifies badly
# accepts a Delete for anyone's post and a Follow from anyone's account, because
# the actor field is a string the sender chose. Every case here is a way
# that could go wrong.
class FediverseSignatureTest < ActiveSupport::TestCase
  setup do
    @key = OpenSSL::PKey::RSA.new(2048)
    @key_id = "https://remote.example/users/kari#main-key"
    @body = { "type" => "Follow", "actor" => "https://remote.example/users/kari" }.to_json
  end

  # A stand-in for ActionDispatch::Request carrying exactly what verify reads.
  FakeRequest = Struct.new(:headers, :method, :fullpath, :host_with_port)

  def signed_request(body: @body, path: "/inbox", host: "brgen.no", key: @key, key_id: @key_id)
    headers = Fediverse::Signature.sign(
      key: key, key_id: key_id, method: :post, url: "https://#{host}#{path}", body: body
    )
    FakeRequest.new(headers, "POST", path, host)
  end

  def verify(request, body: @body, key: @key)
    Fediverse::Signature.verify(request: request, body: body, public_key_for: ->(_) { key.public_key })
  end

  test "a correctly signed request verifies" do
    assert verify(signed_request)
  end

  test "a body swapped after signing does not verify" do
    request = signed_request
    # The Digest header is what ties the signature to this body. Without
    # checking it, a signed request can carry any payload at all.
    refute verify(request, body: { "type" => "Delete" }.to_json)
  end

  test "the wrong key does not verify" do
    other = OpenSSL::PKey::RSA.new(2048)
    refute verify(signed_request, key: other)
  end

  test "an unknown key means refusal, not an exception" do
    result = Fediverse::Signature.verify(
      request: signed_request, body: @body, public_key_for: ->(_) { nil }
    )
    refute result
  end

  # A signature for one path is otherwise valid for another.
  test "replaying a signature against a different path does not verify" do
    request = signed_request(path: "/inbox")
    moved = FakeRequest.new(request.headers, "POST", "/users/someone-else/inbox", "brgen.no")

    refute verify(moved)
  end

  test "an old signature does not verify" do
    request = signed_request
    request.headers["Date"] = (Fediverse::Signature::MAX_AGE + 1.minute).ago.httpdate

    refute verify(request)
  end

  # Partial coverage is the subtle one: a signature over nothing but Date is a
  # perfectly valid signature that proves nothing about this request.
  test "a signature that does not cover the required headers is refused" do
    request = signed_request
    request.headers["Signature"] = request.headers["Signature"].sub('headers="(request-target) host date digest"', 'headers="date"')

    refute verify(request)
  end

  test "a missing signature header is refused" do
    request = FakeRequest.new({ "Date" => Time.now.httpdate }, "POST", "/inbox", "brgen.no")

    refute verify(request)
  end

  test "a missing digest header is refused" do
    request = signed_request
    request.headers.delete("Digest")

    refute verify(request)
  end

  test "parse reads the comma-separated signature parameters" do
    parsed = Fediverse::Signature.parse('keyId="abc",algorithm="rsa-sha256",headers="date",signature="xyz"')

    assert_equal "abc", parsed["keyId"]
    assert_equal "date", parsed["headers"]
    assert_equal "xyz", parsed["signature"]
  end
end
