# frozen_string_literal: true

require "test_helper"

class GroundRedactorTest < Minitest::Test
  def test_text_redacts_api_key_patterns
    raw = "token sk-#{'A' * 24} leaked"
    assert_equal "token [REDACTED] leaked", Master::Ground::Redactor.text(raw)
  end

  def test_payload_redacts_note_text_and_sensitive_keys
    scrubbed = Master::Ground::Redactor.payload(
      text: "sk-#{'B' * 24}",
      token: "secret-value",
      tool: "ReadFile"
    )

    assert_equal "[REDACTED]", scrubbed[:text]
    assert_equal "[REDACTED]", scrubbed[:token]
    assert_equal "ReadFile", scrubbed[:tool]
  end
end