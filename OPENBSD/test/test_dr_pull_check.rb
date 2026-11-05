# frozen_string_literal: true

require "digest"
require "fileutils"
require "minitest/autorun"
require "open3"
require "rbconfig"
require "tmpdir"

class TestDrPullCheck < Minitest::Test
  SCRIPT = File.expand_path("../bin/dr-pull", __dir__)

  def setup
    _version, status = Open3.capture2("sqlite3", "--version")
    skip "sqlite3 CLI unavailable; dr-pull's integrity verifier needs it" unless status.success?

    @root = Dir.mktmpdir("dr-pull-check-")
    @pull = File.join(@root, "20261105-1800")
    FileUtils.mkdir_p(@pull)
    @database = File.join(@pull, "brgen-production.sqlite3")
    _out, error, result = Open3.capture3(
      "sqlite3", @database,
      "CREATE TABLE schema_migrations(version TEXT NOT NULL); INSERT INTO schema_migrations VALUES ('20261105180000'); CREATE TABLE users(id INTEGER PRIMARY KEY);"
    )
    assert result.success?, error
    write_sums
  end

  def teardown
    FileUtils.remove_entry(@root) if @root && File.directory?(@root)
  end

  def test_check_skips_when_no_backup_destination_is_configured
    home = File.join(@root, "no-backup-home")
    FileUtils.mkdir_p(home)
    output, status = Open3.capture2e(
      { "PUB4_DR_DIR" => nil, "HOME" => home },
      RbConfig.ruby, SCRIPT, "--check"
    )

    assert status.success?, output
    assert_includes output, "skip"
  end

  def test_check_fails_when_an_explicitly_configured_destination_is_missing
    missing = File.join(@root, "removed-backup-dir")
    output, status = run_check("PUB4_DR_DIR" => missing)

    refute status.success?
    assert_includes output, "configured backup directory is missing"
  end

  def test_check_verifies_checksum_and_sqlite_integrity
    output, status = run_check

    assert status.success?, output
    assert_includes output, "checksum + integrity verified"
    assert_includes output, "1 database(s)"
  end

  def test_check_keeps_legacy_pulls_without_a_checksum_manifest_integrity_verified
    File.delete(File.join(@pull, "SHA256SUMS"))

    output, status = run_check

    assert status.success?, output
    assert_includes output, "integrity verified; legacy pull has no SHA256SUMS"
    assert_includes output, "WARNING"
  end

  def test_check_rejects_a_checksum_mismatch
    File.write(File.join(@pull, "SHA256SUMS"), "#{Digest::SHA256.hexdigest("wrong")}  brgen-production.sqlite3\n")

    output, status = run_check

    refute status.success?
    assert_includes output, "checksum mismatch"
  end

  def test_check_rejects_an_integrity_failure_even_with_a_matching_checksum
    File.binwrite(@database, "not a sqlite database")
    write_sums

    output, status = run_check

    refute status.success?
    assert_includes output, "integrity_check failed"
  end

  def test_check_rejects_a_symlinked_database
    outside = File.join(@root, "outside.sqlite3")
    FileUtils.mv(@database, outside)
    File.symlink(outside, @database)

    output, status = run_check

    refute status.success?
    assert_includes output, "symlinked database"
  end

  def test_check_does_not_follow_a_symlinked_timestamp_directory
    outside = File.join(@root, "outside")
    FileUtils.mkdir_p(outside)
    FileUtils.mv(@database, File.join(outside, "brgen-production.sqlite3"))
    FileUtils.rm_rf(@pull)
    File.symlink(outside, @pull)

    output, status = run_check

    refute status.success?
    assert_includes output, "no pull with a database"
  end

  private

  def write_sums
    hash = Digest::SHA256.file(@database).hexdigest
    File.write(File.join(@pull, "SHA256SUMS"), "#{hash}  brgen-production.sqlite3\n")
  end

  def run_check(overrides = {})
    Open3.capture2e(
      { "PUB4_DR_DIR" => @root, "PUB4_DR_STALE_DAYS" => "2" }.merge(overrides),
      RbConfig.ruby, SCRIPT, "--check"
    )
  end
end
