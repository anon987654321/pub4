# frozen_string_literal: true

require "minitest/autorun"
require_relative "../replicate/client"

class TestStudioReplicateClientPaths < Minitest::Test
  class StubClient < Studio::ReplicateClient
    attr_reader :requests

    def initialize
      @requests = []
      super(token: "test-token")
    end

    def get(uri)
      @requests << [:get, uri]
      {}
    end

    def post(uri, body, headers: {})
      @requests << [:post, uri, body, headers]
      { "id" => "prediction_123", "status" => "succeeded", "output" => "ok" }
    end
  end

  def setup
    @client = StubClient.new
  end

  def test_pinned_model_reference_is_accepted_without_a_lookup
    version = "a" * 64

    assert_equal "ok", @client.predict("owner/model-name:#{version}", {})

    assert_equal 1, @client.requests.length
    method, uri, body, = @client.requests.fetch(0)
    assert_equal :post, method
    assert_equal "/v1/predictions", uri.path
    assert_equal version, body.fetch(:version)
  end

  def test_model_reference_cannot_escape_its_owner_and_model_segments
    [
      "owner/../account",
      "owner/model/extra",
      "owner/model%2fother",
      "owner",
      "../account/model"
    ].each do |reference|
      error = assert_raises(ArgumentError, reference) do
        @client.run(reference, {})
      end
      assert_match(/owner\/name/, error.message)
    end

    assert_empty @client.requests
  end

  def test_training_destination_must_be_a_single_unpinned_model_reference
    error = assert_raises(ArgumentError) { @client.create_model("owner/model:version") }

    assert_match(/without a version/, error.message)
    assert_empty @client.requests
  end

  def test_training_and_prediction_resource_ids_cannot_be_paths
    assert_raises(ArgumentError) { @client.get_training("../account") }
    assert_nil @client.send(:cancel_prediction, "../account")
    assert_nil @client.send(:cancel_training, "../account")

    assert_empty @client.requests
  end

  def test_training_version_is_validated_before_a_create_request
    error = assert_raises(ArgumentError) do
      @client.train_lora("https://files.replicate.delivery/photos.zip", "owner/model",
                         wait: false, version: "../account")
    end

    assert_match(/trainer version/, error.message)
    assert_equal [:get], @client.requests.map(&:first)
  end

  def test_api_origin_guard_rejects_dot_segments_and_escaped_paths
    [
      "https://api.replicate.com/v1/models/../account",
      "https://api.replicate.com/v1/models/%2e%2e/account",
      "https://api.replicate.com/v1/models/%2faccount",
      "http://api.replicate.com/v1/models",
      "mailto:operator@example.invalid"
    ].each do |url|
      assert_raises(ArgumentError, url) { @client.send(:api_uri, url) }
    end
  end
end
