# frozen_string_literal: true

require "test_helper"

class CspNonceTest < ActionDispatch::IntegrationTest
  def nonce
    header = response.headers["Content-Security-Policy-Report-Only"] || response.headers["Content-Security-Policy"]
    header.to_s[/'nonce-([^']*)'/, 1]
  end

  test "every response carries a fresh, non-blank script nonce" do
    get root_path
    first = nonce
    get root_path

    assert first.present?, "the first visit must not get an empty nonce"
    assert_not_equal first, nonce
    assert_includes response.body, %(nonce="#{nonce}")
  end
end
