# frozen_string_literal: true

require "test_helper"

# TODO.md, rails_coverage_contract_is_tautological: "shared/sso_token
# ... has zero tests; sso_token also has no replay/nonce protection on its 120s
# token." Both are addressed here — the tests came first and the replay test is the
# one that failed before the jti landed.
#
# Note while reading this: nothing in the tree mints these tokens. The consume half
# is wired in all three apps and the MASTER side is not in this repository, so this
# is a dormant entry point being hardened, not a live login path.
class Shared::SsoTokenTest < ActiveSupport::TestCase
  SECRET = "x" * 32

  def with_secret(value = SECRET)
    saved = %w[MASTER_SSO_SECRET MASTER_INTERNAL_TOKEN MASTER_BRIDGE_TOKEN].to_h { |k| [ k, ENV.fetch(k, nil) ] }
    ENV["MASTER_SSO_SECRET"] = value
    ENV.delete("MASTER_INTERNAL_TOKEN")
    ENV.delete("MASTER_BRIDGE_TOKEN")
    yield
  ensure
    saved.each { |k, v| v.nil? ? ENV.delete(k) : ENV[k] = v }
  end

  def mint(**overrides)
    Shared::SsoToken.mint(**{ app: "brgen", email: "Someone@Example.COM " }.merge(overrides))
  end

  test "a freshly minted token verifies once" do
    with_secret do
      payload = Shared::SsoToken.verify(mint, expected_app: "brgen")

      assert_equal "brgen", payload["app"]
      assert_equal "someone@example.com", payload["email"], "email is normalised at mint"
      assert_operator payload["exp"], :>, Time.now.to_i
    end
  end

  # The defect this file exists for: within the 120s window the same URL was a
  # working login for anyone holding it, any number of times.
  test "a token cannot be replayed" do
    with_secret do
      token = mint

      assert Shared::SsoToken.verify(token, expected_app: "brgen"), "first use must succeed"
      assert_nil Shared::SsoToken.verify(token, expected_app: "brgen"), "second use must be refused"
      assert_nil Shared::SsoToken.verify(token, expected_app: "brgen")
    end
  end

  test "two distinct tokens for the same user both work" do
    with_secret do
      assert Shared::SsoToken.verify(mint, expected_app: "brgen")
      assert Shared::SsoToken.verify(mint, expected_app: "brgen")
    end
  end

  test "consume false inspects without spending" do
    with_secret do
      token = mint

      assert Shared::SsoToken.verify(token, expected_app: "brgen", consume: false)
      assert Shared::SsoToken.verify(token, expected_app: "brgen"), "the token was not spent by the inspection"
    end
  end

  test "every minted token carries a unique jti" do
    with_secret do
      ids = 5.times.map { Shared::SsoToken.verify(mint, expected_app: "brgen", consume: false)["jti"] }

      assert_equal 5, ids.uniq.size
      ids.each { |id| refute_nil id }
    end
  end

  test "a tampered payload is refused" do
    with_secret do
      body, sig = mint.split(".", 2)
      forged = Base64.urlsafe_encode64(
        JSON.generate(JSON.parse(Base64.urlsafe_decode64(body)).merge("email" => "admin@example.com")),
        padding: false
      )

      assert_nil Shared::SsoToken.verify("#{forged}.#{sig}", expected_app: "brgen")
    end
  end

  test "a token minted for another app is refused" do
    with_secret do
      assert_nil Shared::SsoToken.verify(mint(app: "amber"), expected_app: "brgen")
    end
  end

  test "an expired token is refused" do
    with_secret do
      assert_nil Shared::SsoToken.verify(mint(ttl: -1), expected_app: "brgen")
    end
  end

  test "garbage and empty input are refused without raising" do
    with_secret do
      [ "", "   ", "nodot", "a.b", "...", Base64.urlsafe_encode64("{}", padding: false) ].each do |bad|
        assert_nil Shared::SsoToken.verify(bad, expected_app: "brgen"), "#{bad.inspect} should be refused"
      end
    end
  end

  test "an unknown app cannot be minted for" do
    with_secret do
      assert_raises(ArgumentError) { mint(app: "nope") }
    end
  end

  test "a short or missing secret means unconfigured, and minting refuses" do
    with_secret("tooshort") do
      refute Shared::SsoToken.configured?
      assert_raises(ArgumentError) { mint }
      assert_nil Shared::SsoToken.verify("anything", expected_app: "brgen")
    end
  end

  # A token signed with a different secret must not verify — the whole point of the
  # HMAC, and the case a constant-time compare has to get right.
  test "a token signed with another secret is refused" do
    token = with_secret("y" * 32) { mint }

    with_secret do
      assert_nil Shared::SsoToken.verify(token, expected_app: "brgen")
    end
  end

  # Links minted before jti existed are still legitimate and unforgeable; refusing
  # them would have broken anything in flight across a deploy.
  test "a legacy token without a jti is still accepted" do
    with_secret do
      payload = {
        "app" => "brgen", "email" => "legacy@example.com", "user_id" => nil,
        "display_name" => nil, "exp" => Time.now.to_i + 60, "iat" => Time.now.to_i, "v" => 1
      }
      body = Base64.urlsafe_encode64(JSON.generate(payload), padding: false)
      token = "#{body}.#{Shared::SsoToken.sign(body)}"

      assert Shared::SsoToken.verify(token, expected_app: "brgen")
    end
  end
end
