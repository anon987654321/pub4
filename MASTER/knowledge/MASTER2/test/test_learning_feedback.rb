# frozen_string_literal: true

require "minitest/autorun"
require "fileutils"
require "json"
require_relative "../lib/master"

class TestLearningFeedback < Minitest::Test
  def setup
    FileUtils.mkdir_p("tmp")
    @db_file = File.join(MASTER.root, MASTER::LearningFeedback::DB_FILE)
    
    # Remove existing DB
    File.delete(@db_file) if File.exist?(@db_file)
  end

  def teardown
    File.delete(@db_file) if File.exist?(@db_file)
  end

  def test_record_creates_db
    finding = MASTER::Audit::Finding.new(
      file: "test.rb",
      line: 1,
      severity: :high,
      effort: :easy,
      category: :naming,
      message: "Test finding",
      suggestion: "Fix it"
    )
    
    result = MASTER::LearningFeedback.record(finding, { type: "rename" }, success: true)
    
    assert result.ok?
    assert File.exist?(@db_file)
  end

  def test_record_appends_to_db
    finding = MASTER::Audit::Finding.new(
      file: "test.rb", line: 1, severity: :high, effort: :easy,
      category: :naming, message: "Test", suggestion: nil
    )
    
    MASTER::LearningFeedback.record(finding, { type: "fix1" }, success: true)
    MASTER::LearningFeedback.record(finding, { type: "fix2" }, success: false)
    
    patterns = MASTER::LearningFeedback.load_patterns
    assert_equal 2, patterns.size
  end

  def test_known_fix_with_sufficient_data
    finding = MASTER::Audit::Finding.new(
      file: "test.rb", line: 1, severity: :high, effort: :easy,
      category: :naming, message: "Bad name", suggestion: nil
    )
    
    # Record multiple successful fixes
    4.times do
      MASTER::LearningFeedback.record(finding, { type: "rename" }, success: true)
    end
    
    assert MASTER::LearningFeedback.known_fix?(finding)
  end

  def test_known_fix_insufficient_data
    finding = MASTER::Audit::Finding.new(
      file: "test.rb", line: 1, severity: :high, effort: :easy,
      category: :naming, message: "Bad name", suggestion: nil
    )
    
    # Only 2 applications - not enough
    2.times do
      MASTER::LearningFeedback.record(finding, { type: "rename" }, success: true)
    end
    
    refute MASTER::LearningFeedback.known_fix?(finding)
  end

  def test_known_fix_low_success_rate
    finding = MASTER::Audit::Finding.new(
      file: "test.rb", line: 1, severity: :high, effort: :easy,
      category: :naming, message: "Bad name", suggestion: nil
    )
    
    # 3 successes, 7 failures = 30% success rate (below 70% threshold)
    3.times { MASTER::LearningFeedback.record(finding, { type: "rename" }, success: true) }
    7.times { MASTER::LearningFeedback.record(finding, { type: "rename" }, success: false) }
    
    refute MASTER::LearningFeedback.known_fix?(finding)
  end

  def test_apply_known_returns_result
    finding = MASTER::Audit::Finding.new(
      file: "test.rb", line: 1, severity: :high, effort: :easy,
      category: :naming, message: "Bad name", suggestion: nil
    )
    
    4.times do
      MASTER::LearningFeedback.record(finding, { type: "rename" }, success: true)
    end
    
    result = MASTER::LearningFeedback.apply_known(finding)
    
    assert result.ok?
  end

  def test_load_patterns_empty_db
    patterns = MASTER::LearningFeedback.load_patterns
    assert_equal [], patterns
  end
end
