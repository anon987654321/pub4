# frozen_string_literal: true

require_relative "test_helper"

class TestLawSourceTree < Minitest::Test
  def test_law_detectors_have_one_canonical_home_and_no_legacy_alias
    canonical = File.join(Master::ROOT, "law", "detectors")
    legacy = File.join(Master::ROOT, "lib", "review", "scan", "laws")

    assert File.directory?(canonical), "canonical detector directory is missing"
    refute File.exist?(legacy), "retired scanner-law path must not be restored"
    refute File.symlink?(legacy), "law source consolidation must not use a compatibility symlink"

    detectors = Dir.glob(File.join(canonical, "*.rb"))
    refute_empty detectors
    detectors.each { |detector| assert File.file?(detector), "missing detector source: #{detector}" }
  end
end
