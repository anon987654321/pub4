# frozen_string_literal: true

require "test_helper"

class IngressControllerTest < ActionDispatch::IntegrationTest
  # A fixed token, so the authenticated paths run on every machine rather
  # than skipping wherever MASTER_INGRESS_TOKEN is unset.
  TOKEN = "ingress-test-token-0123456789"

  def setup
    @previous_token = ENV["MASTER_INGRESS_TOKEN"]
    ENV["MASTER_INGRESS_TOKEN"] = TOKEN
    @token = IngressToken.read
  end

  def teardown
    ENV["MASTER_INGRESS_TOKEN"] = @previous_token
  end

  def test_health_public_hides_job_names
    get "/ingress/health"
    assert_response :success
    body = JSON.parse(response.body)
    assert_equal "master-ingress", body["service"]
    refute body.key?("cron_jobs")
    refute body.key?("webhooks")
  end

  def test_health_lists_job_names_to_the_token_holder
    token = "t" * IngressToken::MIN_TOKEN_LENGTH
    previous = ENV["MASTER_INGRESS_TOKEN"]
    ENV["MASTER_INGRESS_TOKEN"] = token
    get "/ingress/health", headers: { "Authorization" => "Bearer #{token}" }
    assert_includes JSON.parse(response.body)["cron_jobs"], "self_test"
  ensure
    ENV["MASTER_INGRESS_TOKEN"] = previous
  end

  def test_cron_requires_auth
    post "/ingress/cron/self_test"
    assert_response :unauthorized
  end

  def test_cron_unknown_job
    post "/ingress/cron/missing-job-xyz",
         headers: { "Authorization" => "Bearer #{@token}" },
         as: :json
    assert_response :not_found
  end

  def test_cron_with_a_wrong_token_is_unauthorized
    post "/ingress/cron/self_test", headers: { "Authorization" => "Bearer not-the-token-at-all" }, as: :json
    assert_response :unauthorized
  end
end
