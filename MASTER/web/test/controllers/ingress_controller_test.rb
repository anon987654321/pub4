# frozen_string_literal: true

require "test_helper"

class IngressControllerTest < ActionDispatch::IntegrationTest
  def setup
    @token = MasterIngressToken.read
  end

  def test_health_public
    get "/ingress/health"
    assert_response :success
    body = JSON.parse(response.body)
    assert_equal "master-ingress", body["service"]
    assert_includes body["cron_jobs"], "self_test"
  end

  def test_cron_requires_auth
    post "/ingress/cron/self_test"
    assert_response :unauthorized
  end

  def test_cron_unknown_job
    skip "ingress token not configured" if @token.empty?
    post "/ingress/cron/missing-job-xyz",
         headers: { "Authorization" => "Bearer #{@token}" },
         as: :json
    assert_response :not_found
  end
end