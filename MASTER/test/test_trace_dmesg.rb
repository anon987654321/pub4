# frozen_string_literal: true

require "test_helper"

class TraceDmesgTest < Minitest::Test
  def test_dmesg_unit_is_defined_when_logging_is_loaded
    load File.expand_path("../lib/trace/logging.rb", __dir__)

    assert defined?(Master::Trace::DmesgUnit)
    assert_equal "scan0", Master::Trace::DmesgUnit.name("scan")
    assert_includes Master::Trace::DmesgUnit::ATTACHED, "scan"
  end

  def test_zsh_law_is_available_before_shell_class_loads
    banned = Master.law("zsh").fetch("banned_commands")

    assert_equal %w[sed awk tr cut find head tail wc perl python bash], banned
  end
end
