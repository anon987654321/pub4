# frozen_string_literal: true

require "minitest/autorun"
require_relative "../lib/secret_redaction"

# sync.rb's redaction is fail-open no longer. Watched failing before this file
# was trusted: the patterns pinned `_KEY=` values to the sk- prefix, so
# `REPLICATE_KEY=r8_...` mirrored into git verbatim, and a secret matching no
# pattern at all (`smtp_url=smtp://user:pass@...`) had no second line of
# defence. Each probe below pins one of those two findings; the residue tests
# fire only through the audit added with them.
class SyncRedactionTest < Minitest::Test
  R = SecretRedaction

  def test_redacts_provider_keys_beyond_the_sk_prefix
    out = R.redact("REPLICATE_KEY=r8_secret_value123\n")
    assert_equal "REPLICATE_KEY=#{R::PLACEHOLDER}\n", out
  end

  def test_redacts_the_patterns_that_always_worked
    body = "OPENAI_API_KEY=sk-abc\nACCESS_TOKEN=tok\nDB_PASSWORD=pw\nJWT_SECRET=s\n"
    out = R.redact(body)
    %w[OPENAI_API_KEY ACCESS_TOKEN DB_PASSWORD JWT_SECRET].each do |name|
      assert_match %r{^#{name}=#{R::PLACEHOLDER}$}, out, "#{name} must reach the placeholder"
    end
  end

  def test_leaves_ordinary_lines_alone
    body = "PATH=/bin:/usr/local/bin\nlisten on 127.0.0.1\n"
    assert_equal body, R.redact(body)
  end

  def test_residue_empty_when_the_patterns_caught_everything
    assert_empty R.residue("REPLICATE_KEY=r8_secret_value123\nAPI_TOKEN=tok\n")
  end

  def test_residue_flags_a_secret_the_patterns_never_learned
    left = R.residue("smtp_url=smtp://user:pass@mail.brgen.no\n")
    assert_equal 1, left.size
    assert_includes left.first, "smtp_url"
  end

  def test_residue_ignores_lines_it_redacted_itself
    assert_empty R.residue("API_KEY=__REDACTED__\n")
  end

  def test_residue_ignores_empty_values_and_public_names
    assert_empty R.residue("KEY=\nmoniker=brgen\n")
  end

  def test_sync_refuses_files_the_audit_flags
    # The refusal itself runs only on vm23, so this pins the contract at the
    # source: sync.rb must call the audit and must refuse what it flags.
    src = File.read(File.expand_path("../sync.rb", __dir__))
    assert_includes src, "SecretRedaction.residue"
    assert_includes src, "refused", "a flagged file must be refused, not warned"
    assert_match(/exit 3 if refused/, src)
  end
end
