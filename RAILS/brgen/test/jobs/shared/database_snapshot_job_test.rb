# frozen_string_literal: true

require "test_helper"
require "tmpdir"

class Shared::DatabaseSnapshotJobTest < ActiveSupport::TestCase
  # VACUUM INTO cannot run inside a transaction, and in production the job runs
  # outside one; drop the per-test transaction so the test exercises the real path.
  self.use_transactional_tests = false

  test "writes a gzipped point-in-time snapshot of the primary database" do
    Dir.mktmpdir do |dir|
      ENV["PUB4_BACKUP_DIR"] = dir
      result = Shared::DatabaseSnapshotJob.new.perform
      assert File.exist?(result), "the snapshot file should exist"
      assert_match(/production-\d{8}-\d{6}\.sqlite3\.gz\z/, result)
      assert_operator File.size(result), :>, 0, "the snapshot should not be empty"
    ensure
      ENV.delete("PUB4_BACKUP_DIR")
    end
  end
end
