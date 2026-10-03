# frozen_string_literal: true

require_relative "test_helper"
require "sqlite3"

class TestKnowledgeStoreFixQuality < Minitest::Test
  # A violation skipped by policy (confidence gate, stale fingerprint) was
  # never actually attempted -- counting it the same as a genuine failed
  # fix silently poisons that rule's quality score every time the gate
  # fires, without it ever having actually failed. fix_quality/top_rules
  # must exclude 'skipped' from the denominator, matching OpenCrabs'
  # feedback_policy.rs lesson (recorded, but never counted against success).
  def test_skipped_outcomes_are_recorded_but_excluded_from_quality
    Dir.mktmpdir do |root|
      store = Master::Ground::KnowledgeStore.new(root:)
      store.record(rule: "TEST_RULE", file_type: "rb", outcome: "fixed")
      3.times { store.record(rule: "TEST_RULE", file_type: "rb", outcome: "skipped") }

      # 1/1 real attempts succeeded -- skipped attempts must not dilute this.
      assert_in_delta 1.0, store.fix_quality(rule: "TEST_RULE"), 0.001
    ensure
      store&.close
    end
  end

  def test_skipped_only_history_returns_neutral_default
    Dir.mktmpdir do |root|
      store = Master::Ground::KnowledgeStore.new(root:)
      3.times { store.record(rule: "TEST_RULE", file_type: "rb", outcome: "skipped") }

      assert_in_delta 0.5, store.fix_quality(rule: "TEST_RULE"), 0.001
    ensure
      store&.close
    end
  end

  def test_fixed_and_stuck_mix_computes_real_quality
    Dir.mktmpdir do |root|
      store = Master::Ground::KnowledgeStore.new(root:)
      2.times { store.record(rule: "TEST_RULE", file_type: "rb", outcome: "fixed") }
      2.times { store.record(rule: "TEST_RULE", file_type: "rb", outcome: "stuck") }

      assert_in_delta 0.5, store.fix_quality(rule: "TEST_RULE"), 0.001
    ensure
      store&.close
    end
  end

  # Pre-existing DBs had a CHECK (outcome IN ('fixed','stuck')) constraint --
  # inserting 'skipped' would silently fail (swallowed by the rescue) unless
  # the table gets migrated on open.
  def test_migrates_a_pre_existing_db_with_the_old_check_constraint
    Dir.mktmpdir do |root|
      db_path = File.join(root, ".master", "knowledge.sqlite3")
      FileUtils.mkdir_p(File.dirname(db_path))
      old_db = SQLite3::Database.new(db_path)
      old_db.execute_batch(<<~SQL)
        CREATE TABLE fix_outcomes (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          ts INTEGER NOT NULL,
          rule TEXT NOT NULL,
          file_type TEXT NOT NULL,
          outcome TEXT NOT NULL CHECK (outcome IN ('fixed', 'stuck'))
        );
        INSERT INTO fix_outcomes (ts, rule, file_type, outcome) VALUES (#{Time.now.to_i}, 'OLD_RULE', 'rb', 'fixed');
      SQL
      old_db.close

      store = Master::Ground::KnowledgeStore.new(root:)
      store.record(rule: "OLD_RULE", file_type: "rb", outcome: "skipped")

      assert_in_delta 1.0, store.fix_quality(rule: "OLD_RULE"), 0.001
    ensure
      store&.close
    end
  end
end
