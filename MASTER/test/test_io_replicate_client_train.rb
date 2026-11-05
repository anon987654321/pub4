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

  def test_model_pagination_refuses_an_external_cursor_before_sending_its_token
    client = Client.new(token: "replicate-test-secret")
    requests = []
    first = Struct.new(:code, :body).new(
      "200",
      JSON.generate("results" => [], "next" => "https://attacker.invalid/v1/models?cursor=secret"),
    )

    with_http_responses([first], requests) do
      error = assert_raises(ArgumentError) { client.models }
      assert_match(/outside the Replicate API origin/, error.message)
    end

    assert_equal 1, requests.size
    assert_equal "Token", requests.first["Authorization"].split(" ").first
    refute requests.any? { |request| request["Host"] == "attacker.invalid" }
  end

  def test_model_pagination_rejects_a_repeated_cursor_without_a_second_request
    client = Client.new(token: "replicate-test-secret")
    requests = []
    page = Struct.new(:code, :body).new(
      "200",
      JSON.generate("results" => [], "next" => "#{Client::BASE}/models"),
    )

    with_http_responses([page], requests) do
      error = assert_raises(ArgumentError) { client.models }
      assert_match(/repeated a cursor/, error.message)
    end

    assert_equal 1, requests.size
  end

  def test_model_pagination_accepts_only_the_models_cursor_on_the_api_origin
    client = Client.new(token: "replicate-test-secret")
    requests = []
    pages = [
      Struct.new(:code, :body).new(
        "200",
        JSON.generate(
          "results" => [{ "owner" => "first", "name" => "model" }],
          "next" => "https://api.replicate.com/v1/models?cursor=page-two",
        ),
      ),
      Struct.new(:code, :body).new(
        "200",
        JSON.generate("results" => [{ "owner" => "second", "name" => "model" }], "next" => nil),
      ),
    ]

    with_http_responses(pages, requests) { assert_equal 2, client.models.size }

    assert_equal 2, requests.size
    assert requests.all? { |request| request["Authorization"] == "Token replicate-test-secret" }
    assert requests.all? { |request| request.path.start_with?("/v1/models") }
  end

  def test_api_request_uses_explicit_connection_and_read_timeouts
    client = Client.new(token: "replicate-test-secret")
    request = nil
    response = Struct.new(:code, :body).new("200", "{}")
    http = Object.new
    http.define_singleton_method(:request) { |value| request = value; response }

    Net::HTTP.stub(:start, lambda { |host, port, **options, &block|
      assert_equal "api.replicate.com", host
      assert_equal 443, port
      assert_equal true, options.fetch(:use_ssl)
      assert_equal Client::OPEN_TIMEOUT_SECONDS, options.fetch(:open_timeout)
      assert_equal Client::READ_TIMEOUT_SECONDS, options.fetch(:read_timeout)
      block.call(http)
    }) do
      client.account_username
    end

    assert_equal "Token replicate-test-secret", request["Authorization"]
  end

  def test_replicate_token_files_must_be_private_regular_user_files
    Dir.mktmpdir do |directory|
      path = File.join(directory, "env")
      File.write(path, "REPLICATE_API_TOKEN=secret\n")
      File.chmod(0o600, path)
      assert Client.private_token_file?(path)

      File.chmod(0o640, path)
      refute Client.private_token_file?(path)

      File.chmod(0o600, path)
      target = File.join(directory, "secret")
      File.rename(path, target)
      File.symlink(target, path)
      refute Client.private_token_file?(path)
    end
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
