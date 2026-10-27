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

  # The review comment arrived on 2026-10-25 (0a2dce650). Migrations from
  # before it have run everywhere and are history, never edited to satisfy a
  # later rule, so the rule reads only migrations written after it.
  REVIEW_RULE_SINCE = "20261025154230"

  def test_migrations_review_each_destructive_table_drop
    Dir.glob(File.join(ROOT, "{brgen,amber,bsdports}", "db/migrate/*.rb")).each do |path|
      next if File.basename(path) < REVIEW_RULE_SINCE

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
