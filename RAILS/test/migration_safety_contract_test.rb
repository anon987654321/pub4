# frozen_string_literal: true

require "minitest/autorun"

class MigrationSafetyContractTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)

  def test_concurrent_index_migrations_disable_transactions
    Dir.glob(File.join(ROOT, "{brgen,amber,bsdports}", "db/migrate/*.rb")).each do |path|
      source = File.read(path)
      next unless source.include?("algorithm: :concurrently")

      assert_includes source, "disable_ddl_transaction!",
        "#{path} uses a concurrent index without disabling the DDL transaction"
    end
  end

  def test_migrations_do_not_use_unbounded_destructive_helpers
    Dir.glob(File.join(ROOT, "{brgen,amber,bsdports}", "db/migrate/*.rb")).each do |path|
      source = File.read(path)
      assert_equal 0, source.scan(/\bdrop_table\b/).length,
        "#{path} must not drop tables without an explicit safety review"
    end
  end
end
