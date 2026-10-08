# frozen_string_literal: true

require_relative "test_helper"
require_relative "../tools/security_sweep"

# The password rule was a bare regex over whole files, so it flagged sixteen i18n
# strings across brgen and bsdports ("Glemt passord?", "Confirm password",
# "Update your password") and both the contributor and operator check profiles
# failed on translated UI copy. Narrowing a secret detector is exactly the change
# that needs tests on both sides — the rule is worthless if it stops catching real
# credentials.
class TestSecuritySweep < Minitest::Test
  def hits(line) = password_hits(line)

  def test_catches_real_looking_credentials
    [
      %(password: "hunter2!xyz"),
      %(password = "s3cr3t-value"),
      %(PASSWORD: "aVeryLongPassphraseHere"),
      %(password: "9f3a11c8de7b4a2f"),
    ].each do |line|
      refute_empty hits(line), "should still flag #{line.inspect}"
    end
  end

  def test_ignores_translated_interface_copy
    [
      %(forgot_password: "Glemt passord?"),
      %(confirm_password: "Bekreft passord"),
      %(update_password: "Update your password"),
      %(password: "Password"),
      %(new_password: "Nytt passord"),
    ].each do |line|
      assert_empty hits(line), "should not flag #{line.inspect}"
    end
  end

  def test_ignores_documented_placeholders
    [%(password: "changeme"), %(password: "password123"), %(password: "[your password]")].each do |line|
      assert_empty hits(line), "should not flag #{line.inspect}"
    end
  end

  # A long single word is not prose; that is where a passphrase hides.
  def test_a_long_wordlike_value_is_still_suspicious
    refute_empty hits(%(password: "correcthorsebatterystaple"))
  end

  def test_ignores_a_value_that_is_only_an_indirection
    [
      %(password: "$FLOW_AMBER_PASSWORD"),
      %(password: "${DEPLOY_PASSWORD}"),
      %(password: "%{account_password}"),
      %(password: "<%= credentials.password %>"),
    ].each do |line|
      assert_empty hits(line), "should not flag #{line.inspect}"
    end
  end

  # The exemption is the whole value, not a prefix of it: a credential with a
  # variable glued to the front is still a credential.
  def test_an_indirection_beside_a_literal_is_still_suspicious
    refute_empty hits(%(password: "$PREFIX-hunter2!xyz"))
  end

  def test_the_committed_locale_files_are_clean_under_the_rule
    repo = File.expand_path("../..", __dir__)
    Dir.glob(File.join(repo, "RAILS", "*", "config", "locales", "*.yml")).each do |path|
      assert_empty password_hits(File.read(path)), "#{path} would fail the sweep"
    end
  end

  def test_the_sweep_still_reports_the_repo_as_clean
    failures, = sweep

    assert_empty failures
  end
end
