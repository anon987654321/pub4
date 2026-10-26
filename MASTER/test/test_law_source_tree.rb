# frozen_string_literal: true

require_relative "test_helper"

class TestLawSourceTree < Minitest::Test
  def test_executable_law_sources_have_one_canonical_home
    canonical = File.join(Master::ROOT, "law", "detectors")
    compatibility = File.join(Master::ROOT, "lib", "review", "scan", "laws")

    assert File.directory?(canonical), "the canonical detector directory is missing"
    assert File.symlink?(compatibility), "the former scanner-law directory must remain a compatibility symlink"
    assert_equal File.realpath(canonical), File.realpath(compatibility)

    canonical_sources = Dir.glob(File.join(canonical, "*.rb")).map { |path| File.realpath(path) }.sort
    compatibility_sources = Dir.glob(File.join(compatibility, "*.rb")).map { |path| File.realpath(path) }.sort

    refute_empty canonical_sources
    assert_equal canonical_sources, compatibility_sources,
                 "compatibility loading must resolve to the same physical source files"
  end
end
