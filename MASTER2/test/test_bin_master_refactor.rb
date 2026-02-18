# frozen_string_literal: true

require "minitest/autorun"

class TestBinMasterRefactor < Minitest::Test
  def setup
    @bin_master = File.expand_path("../bin/master", __dir__)
    @system_commands = File.expand_path("../lib/commands/system_commands.rb", __dir__)
  end

  def test_bin_master_exists
    assert File.exist?(@bin_master)
  end

  def test_bin_master_executable
    assert File.executable?(@bin_master)
  end

  def test_bin_master_syntax_valid
    assert system("ruby -c #{@bin_master} > /dev/null 2>&1")
  end

  def test_bin_master_reduced_line_count
    lines = File.readlines(@bin_master).size
    assert lines < 300
  end

  def test_bin_master_has_frozen_string_literal
    content = File.read(@bin_master)
    assert_match(/frozen_string_literal: true/, content)
  end

  def test_bin_master_has_minimal_case_branches
    case_branches = File.readlines(@bin_master).grep(/^when /).size
    assert case_branches < 10
  end

  def test_system_commands_module_exists
    assert File.exist?(@system_commands)
  end

  def test_system_commands_syntax_valid
    assert system("ruby -c #{@system_commands} > /dev/null 2>&1")
  end

  def test_helper_methods_exist_in_bin_master
    content = File.read(@bin_master)
    assert_match(/def run_selfrun/, content)
    assert_match(/def delegate_to_commands/, content)
    assert_match(/def run_phase1/, content)
  end

  def test_version_command_still_in_bin_master
    content = File.read(@bin_master)
    assert_match(/when "version"/, content)
    assert_match(/when "help"/, content)
  end

  def test_delegated_commands_removed_from_bin_master
    content = File.read(@bin_master)
    refute_match(/when "refactor"\s*$/, content)
    refute_match(/when "fix"\s*$/, content)
    refute_match(/when "chamber"\s*$/, content)
  end
end
