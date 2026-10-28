# frozen_string_literal: true

require_relative "test_helper"
require "json"

class TestReplicateClientTrain < Minitest::Test
  def test_training_weights_url_from_hash
    client = Master::Io::ReplicateClient.new(token: "r8_test")
    training = {
      "output" => {
        "version" => "owner/model:abc",
        "weights" => "https://replicate.delivery/yhqm/example/trained_model.tar",
      },
    }
    assert_equal(
      "https://replicate.delivery/yhqm/example/trained_model.tar",
      client.training_weights_url(training),
    )
  end

  def test_training_weights_url_string_output
    client = Master::Io::ReplicateClient.new(token: "r8_test")
    assert_equal "owner/model:abc", client.training_weights_url("output" => "owner/model:abc")
  end

  def test_lora_trainer_constant
    assert_equal "ostris/flux-dev-lora-trainer", Master::Io::ReplicateClient::LORA_TRAINER
  end

  def test_create_model_requires_owner_name
    client = Master::Io::ReplicateClient.new(token: "r8_test")
    assert_raises(ArgumentError) { client.create_model("noneslash") }
  end
end

class TestReplicateClientRetry < Minitest::Test
  Client = Master::Io::ReplicateClient

  def with_http_responses(responses, requests)
    http = Object.new
    http.define_singleton_method(:request) do |request|
      requests << request
      responses.shift || raise("unexpected HTTP request")
    end
    starter = lambda { |_host, _port, **_options, &block| block.call(http) }

    Net::HTTP.stub(:start, starter) { yield }
  end

  def test_paid_post_is_not_retried_after_an_ambiguous_server_error
    client = Client.new(token: "r8_test")
    requests = []
    failure = Struct.new(:code, :body).new("500", '{"detail":"internal server error"}')

    error = nil
    with_http_responses([failure], requests) do
      error = assert_raises(Client::TransientError) do
        client.create_model("owner/lora")
      end
    end

    assert_match(/500/, error.message)
    assert_equal ["POST"], requests.map(&:method),
                 "a 5xx may follow a successful paid create; do not blindly replay it"
  end

  def test_explicit_throttle_can_retry_post
    client = Client.new(token: "r8_test")
    client.define_singleton_method(:sleep) { |_seconds| }
    requests = []
    throttled = Struct.new(:code, :body).new("429", '{"detail":"Request was throttled; resets in ~1s."}')
    accepted = Struct.new(:code, :body).new("200", '{"id":"p1"}')

    result = with_http_responses([throttled, accepted], requests) do
      client.create_model("owner/lora")
    end

    assert_equal({ "id" => "p1" }, result)
    assert_equal 2, requests.length
  end

  def test_exhausted_budget_refusal_is_not_retried
    client = Client.new(token: "r8_test")
    requests = []
    exhausted = Struct.new(:code, :body).new("429", '{"detail":"Insufficient credit balance"}')

    Master::Io::QuotaCheck.stub(:trip!, ->(**_args) {}) do
      error = nil
      with_http_responses([exhausted], requests) do
        error = assert_raises(Client::ExhaustedError) do
          client.create_model("owner/lora")
        end
      end
      assert_match(/429/, error.message)
    end

    assert_equal 1, requests.length, "budget refusal cannot be fixed by a timed retry"
  end

  def test_get_keeps_retrying_a_transient_server_error
    client = Client.new(token: "r8_test")
    client.define_singleton_method(:sleep) { |_seconds| }
    requests = []
    failed = Struct.new(:code, :body).new("500", '{"detail":"temporary server fault"}')
    accepted = Struct.new(:code, :body).new("200", '{"results":[{"name":"lora"}]}')

    result = with_http_responses([failed, accepted], requests) do
      client.models(limit: 1)
    end

    assert_equal([{ "name" => "lora" }], result)
    assert_equal 2, requests.length
  end
end
