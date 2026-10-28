# frozen_string_literal: true

require_relative "test_helper"
require_relative "../lib/trace/event_privacy"
require "json"

class TestEventPrivacy < Minitest::Test
  def test_unknown_nested_objects_and_arrays_are_digest_only
    nested = {
      authorization: "Bearer nested-secret",
      metadata: { query: "private search", session: "session-secret" }
    }
    labels = ["private label", "another secret"]
    persisted = Master::Trace::EventPrivacy.persisted(
      "route:chosen",
      status: "ok", metadata: nested, labels:, elapsed_ms: 120
    )
    json = JSON.generate(persisted)

    assert_equal "ok", persisted.fetch(:status)
    assert_equal 120, persisted.fetch(:elapsed_ms)
    assert_equal 64, persisted.fetch(:metadata_digest).length
    assert_equal JSON.generate(nested).bytesize, persisted.fetch(:metadata_bytes)
    assert_equal 64, persisted.fetch(:labels_digest).length
    assert_equal JSON.generate(labels).bytesize, persisted.fetch(:labels_bytes)
    refute_includes json, "nested-secret"
    refute_includes json, "private search"
    refute_includes json, "session-secret"
    refute_includes json, "private label"
    refute_includes json, "another secret"
  end

  def test_undeclared_scalar_strings_are_digest_only_but_model_metadata_is_kept
    persisted = Master::Trace::EventPrivacy.persisted(
      "route:chosen",
      label: "private user-provided label",
      custom_value: "token=private",
      model: "grok-cli:auto",
      provider: "anthropic"
    )
    json = JSON.generate(persisted)

    assert_equal "grok-cli:auto", persisted.fetch(:model)
    assert_equal "anthropic", persisted.fetch(:provider)
    assert_equal 64, persisted.fetch(:label_digest).length
    assert_equal 64, persisted.fetch(:custom_value_digest).length
    refute_includes json, "private user-provided label"
    refute_includes json, "token=private"
  end

  def test_malformed_reserved_metadata_is_digest_only
    persisted = Master::Trace::EventPrivacy.persisted(
      "route:chosen",
      status: "private status token=secret",
      elapsed_ms: "duration token=secret",
      success: "secret-not-a-boolean"
    )
    json = JSON.generate(persisted)

    assert_equal 64, persisted.fetch(:status_digest).length
    assert_equal 64, persisted.fetch(:elapsed_ms_digest).length
    assert_equal 64, persisted.fetch(:success_digest).length
    refute_includes json, "private status token=secret"
    refute_includes json, "duration token=secret"
    refute_includes json, "secret-not-a-boolean"
  end

  def test_common_identity_and_location_fields_are_digest_only
    private_fields = {
      username: "private-user",
      email: "person@example.invalid",
      address: "1 Private Road",
      display_name: "Private Person",
      details: "confidential details",
      value: "one-time-token-value"
    }
    persisted = Master::Trace::EventPrivacy.persisted("profile:updated", private_fields)
    json = JSON.generate(persisted)

    private_fields.each do |field, value|
      assert_equal 64, persisted.fetch("#{field}_digest".to_sym).length
      refute_includes json, value
    end
  end

  def test_sensitive_scalars_remain_digest_only
    persisted = Master::Trace::EventPrivacy.persisted(
      "route:chosen", query: "https://internal.invalid/?token=secret", outcome: "ok"
    )

    assert_equal "ok", persisted.fetch(:outcome)
    assert_equal 64, persisted.fetch(:query_digest).length
    refute_includes JSON.generate(persisted), "token=secret"
  end
end
