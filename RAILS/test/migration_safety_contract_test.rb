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

  def test_migrations_review_each_destructive_table_drop
    Dir.glob(File.join(ROOT, "{brgen,amber,bsdports}", "db/migrate/*.rb")).each do |path|
      lines = File.readlines(path, chomp: true)
      lines.each_with_index do |line, index|
        next unless line.match?(/\bdrop_table\b/)

        context = lines[[index - 3, 0].max...index].join("\n")
        assert_includes context, "migration-safety-reviewed:",
                        "#{path}:#{index + 1} drops a table without a local safety rationale"
      end
    end
  end
end
