# frozen_string_literal: true

require_relative "test_helper"

class TestForbiddenPatternsGuard < Minitest::Test
  def test_lib_contains_no_marshal_load_literal
    matches = Dir.glob(File.join(Master::ROOT, "lib", "**", "*.rb")).filter_map do |path|
      "#{path}: Marshal.load" if File.read(path).include?("Marshal.load")
    end

    assert_empty matches
  end
end
