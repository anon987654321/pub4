# frozen_string_literal: true

require "test_helper"

class DomainsControllerTest < ActionDispatch::IntegrationTest
  test "domain check returns simulator result" do
    get "/domains/check", params: { domain: "example.er" }

    assert_response :success
    body = JSON.parse(response.body)
    assert_equal "example.er", body.fetch("domain")
    assert_equal true, body.fetch("available")
    assert_equal "simulator", body.fetch("source")
    assert_equal "accepted", body.fetch("policy")
  end

  test "domain check rejects unsupported namespaces before registry access" do
    get "/domains/check", params: { domain: "example.com" }

    assert_response :unprocessable_entity
    body = JSON.parse(response.body)
    assert_equal "rejected", body.fetch("policy")
    assert_equal false, body.fetch("available")
  end
end
