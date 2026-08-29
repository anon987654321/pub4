# frozen_string_literal: true

require_relative "test_helper"
require "json"

class TestReplicateClientTrain < Minitest::Test
  def test_training_weights_url_from_hash
    client = Master::Io::ReplicateClient.allocate
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
    client = Master::Io::ReplicateClient.allocate
    assert_equal "owner/model:abc", client.training_weights_url("output" => "owner/model:abc")
  end

  def test_lora_trainer_constant
    assert_equal "ostris/flux-dev-lora-trainer", Master::Io::ReplicateClient::LORA_TRAINER
  end

  def test_create_model_requires_owner_name
    client = Master::Io::ReplicateClient.allocate
    assert_raises(ArgumentError) { client.create_model("noneslash") }
  end
end
