# frozen_string_literal: true

require "test_helper"

# /internal/version is the one place that says which commit the serving
# process booted, behind the same shared token as /internal/status.
class InternalVersionTest < ActionDispatch::IntegrationTest
  TOKEN = "internal-version-test-token"

  def setup
    # brgen resolves city, locale and branding from the request host; a test's
    # default www.example.com is an unknown host and renders the styled 404
    # before the action runs. MASTER calls the endpoint on brgen.no.
    host! "brgen.no"
    @previous_token = ENV["MASTER_INTERNAL_TOKEN"]
    ENV["MASTER_INTERNAL_TOKEN"] = TOKEN
  end

  def teardown
    if @previous_token.nil?
      ENV.delete("MASTER_INTERNAL_TOKEN")
    else
      ENV["MASTER_INTERNAL_TOKEN"] = @previous_token
    end
  end

  def test_version_reports_the_running_revision_behind_the_token
    get internal_version_path, headers: { "X-Internal-Token" => TOKEN }

    assert_response :success
    body = JSON.parse(response.body)
    assert_equal "brgen", body.fetch("app")
    assert_predicate body.fetch("revision"), :present?
  end

  def test_version_refuses_a_caller_without_a_token
    get internal_version_path

    assert_response :unauthorized
  end

  def test_version_refuses_a_wrong_token
    get internal_version_path, headers: { "X-Internal-Token" => "not-the-token" }

    assert_response :unauthorized
  end
end
