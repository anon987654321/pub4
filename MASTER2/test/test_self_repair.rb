# frozen_string_literal: true

require "minitest/autorun"
require "fileutils"
require_relative "../lib/master"

class TestSelfRepair < Minitest::Test
  def setup
    FileUtils.mkdir_p("tmp")
    @test_file = "tmp/test_repair.rb"
    
    # Create a file with issues
    content = "# frozen_string_literal: true\n" + ("puts 'line'\n" * 300)
    File.write(@test_file, content)
  end

  def teardown
    File.delete(@test_file) if File.exist?(@test_file)
  end

  def test_repair_with_dry_run
    result = MASTER::SelfRepair.repair(@test_file, dry_run: true)
    
    assert result.ok?
    assert_equal 0, result.value[:repaired]
    assert result.value[:skipped] >= 0
  end

  def test_repair_returns_result_structure
    result = MASTER::SelfRepair.repair(@test_file, dry_run: true)
    
    assert result.ok?
    assert result.value.key?(:repaired)
    assert result.value.key?(:failed)
    assert result.value.key?(:skipped)
    assert result.value.key?(:total)
  end

  def test_repair_with_auto_confirm
    result = MASTER::SelfRepair.repair(@test_file, dry_run: true, auto_confirm: true)
    
    assert result.ok?
  end

  def test_repair_requires_audit_module
    # This is implicitly tested - if Audit is not available, repair fails
    result = MASTER::SelfRepair.repair(@test_file, dry_run: true)
    
    # Should succeed since Audit is loaded
    assert result.ok?
  end

  def test_repair_accepts_array_of_files
    result = MASTER::SelfRepair.repair([@test_file], dry_run: true)
    
    assert result.ok?
  end
end
