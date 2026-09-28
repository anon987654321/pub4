# frozen_string_literal: true

require "minitest/autorun"

class RecoveryContractTest < Minitest::Test
  ROOT = File.expand_path("../..", __dir__)

  def test_restic_backup_requires_explicit_repository_and_password_source
    source = File.read(File.join(ROOT, "OPENBSD/bin/dr-backup"))
    assert_includes source, 'ENV["RESTIC_REPOSITORY"]'
    assert_includes source, 'ENV["RESTIC_PASSWORD_FILE"]'
    assert_includes source, 'ENV["PUB4_DB_PATHS"]'
    assert_includes source, '"restic", "backup"'
  end

  def test_idempotency_releases_failed_mutation_lock
    source = File.read(File.join(ROOT, "RAILS/shared/app/controllers/concerns/shared/idempotency.rb"))
    assert_includes source, 'if response.status >= 500'
    assert_includes source, "Rails.cache.delete(idempotency_cache_key)"
    assert_includes source, '"X-Idempotency-Key"'
  end
end
