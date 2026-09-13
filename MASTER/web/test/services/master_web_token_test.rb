# frozen_string_literal: true

require "test_helper"
require "tmpdir"

# AuthTier seeds the operator token and MasterWebToken reads it back, each with
# its own length floor. If the floors part, a token one side accepts reads as
# empty on the other, and every authenticated request fails closed.
class MasterWebTokenTest < ActiveSupport::TestCase
  test "the reader and the seeder agree on the shortest acceptable token" do
    assert_equal AuthTier::MIN_TOKEN_LENGTH, MasterWebToken::MIN_LENGTH
  end

  test "a seeded token clears the floor both sides enforce" do
    seeded = SecureRandom.urlsafe_base64(AuthTier::TOKEN_BYTES)

    assert_operator seeded.length, :>=, AuthTier::MIN_TOKEN_LENGTH
  end

  test "a token under the floor reads as empty" do
    Dir.mktmpdir do |dir|
      path = File.join(dir, "config.yml")
      File.write(path, { "web_token" => "x" * (MasterWebToken::MIN_LENGTH - 1) }.to_yaml)
      previous = ENV["MASTER_AUTH_CONFIG"]
      ENV["MASTER_AUTH_CONFIG"] = path

      assert_equal "", MasterWebToken.read
    ensure
      ENV["MASTER_AUTH_CONFIG"] = previous
    end
  end
end
