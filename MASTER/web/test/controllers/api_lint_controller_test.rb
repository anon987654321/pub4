# frozen_string_literal: true

require "test_helper"

class ApiLintControllerTest < ActionDispatch::IntegrationTest
  setup do
    subscription = { "id" => "sub_api_2", "status" => "active", "customer" => "cus_2",
                     "metadata" => { "plan" => "master_api_team" } }
    @key = ApiKey.sync!(subscription)
    @token = @key.reveal!
  end

  def lint(files, token: @token)
    post "/api/v1/lint", params: { files: }.to_json,
                         headers: { "Authorization" => "Bearer #{token}", "Content-Type" => "application/json" }
  end

  test "a valid key gets findings and its usage" do
    lint([{ path: "app/models/a.rb", source: "class A\n  def a(x) = x ? 1 : 1\nend\n" }])

    assert_response :success
    body = response.parsed_body
    assert_includes body["findings"].map { |finding| finding["law"] }, "IDENTICAL_BRANCHES"
    assert_equal 1, body.dig("usage", "used")
  end

  test "a wrong key is refused before anything is scanned or counted" do
    lint([{ path: "a.rb", source: "" }], token: "mk_live_wrong")

    assert_response :unauthorized
    assert_equal 0, @key.reload.usage_count
  end

  test "a lapsed subscription pays nothing and gets 402" do
    @key.update!(status: "past_due")
    lint([{ path: "a.rb", source: "" }])

    assert_response :payment_required
  end

  test "a path outside the project is refused" do
    lint([{ path: "../../etc/passwd", source: "" }])

    assert_response :unprocessable_entity
    assert_equal 0, @key.reload.usage_count
  end

  test "an exhausted quota answers 429 with the usage" do
    @key.update!(usage_period: ApiKey.current_period, usage_count: @key.quota)
    lint([{ path: "a.rb", source: "" }])

    assert_response :too_many_requests
    assert_equal "quota_exhausted", response.parsed_body["error"]
  end
end
