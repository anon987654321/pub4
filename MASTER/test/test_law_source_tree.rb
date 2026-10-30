# frozen_string_literal: true

require_relative "test_helper"

class TestLawSourceTree < Minitest::Test
  # One flat law/: every Law file sits directly in it. law/detectors/ (split by
  # detector kind) and law/definition/ (split by line count) were technical
  # layers, and lib/review/scan/laws/ an older home; none may come back.
  def test_laws_have_one_flat_home_and_no_legacy_alias
    home = File.join(Master::ROOT, "law")
    retired = [File.join(home, "detectors"), File.join(home, "definition"),
               File.join(Master::ROOT, "lib", "review", "scan", "laws")]

    refute_empty Dir.glob(File.join(home, "*.rb"))
    assert_empty Dir.glob(File.join(home, "*", "**", "*.rb")), "Law files sit directly in law/"
    retired.each do |path|
      refute File.exist?(path), "retired Law path must not be restored: #{path}"
      refute File.symlink?(path), "law source consolidation must not use a compatibility symlink: #{path}"
    end
  end
end
