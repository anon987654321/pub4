# frozen_string_literal: true

require "test_helper"

class GroundRedactorTest < Minitest::Test
  def test_text_redacts_api_key_patterns
    raw = "token sk-#{'A' * 24} leaked"
    assert_equal "token [REDACTED] leaked", Master::Ground::Redactor.text(raw)
  end

  def test_payload_terminates_on_a_self_referential_hash
    raw = {}
    raw[:child] = raw

    scrubbed = Master::Ground::Redactor.payload(raw)

    assert_equal "[CYCLE]", scrubbed[:child]
  end

  def test_payload_terminates_on_a_self_referential_array
    raw = []
    raw << raw

    scrubbed = Master::Ground::Redactor.payload({ value: raw })

    assert_equal "[CYCLE]", scrubbed[:value][0]
  end

  def test_payload_terminates_on_a_hash_array_hash_cycle
    hash = {}
    array = []
    hash[:array] = array
    array << hash

    scrubbed = Master::Ground::Redactor.payload(hash)

    assert_equal "[CYCLE]", scrubbed[:array][0]
  end

  def test_payload_redacts_note_text_and_sensitive_keys
    scrubbed = Master::Ground::Redactor.payload(
      text: "sk-#{'B' * 24}",
      token: "secret-value",
      tool: "ReadFile",
    )

    assert_equal "[REDACTED]", scrubbed[:text]
    assert_equal "[REDACTED]", scrubbed[:token]
    assert_equal "ReadFile", scrubbed[:tool]
  end
end
