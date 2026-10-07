# frozen_string_literal: true

require "test_helper"

class TestVersion < Minitest::Test
  def test_release_version_comes_from_the_root_version_file
    expected = File.read(File.expand_path("../../VERSION", __dir__), encoding: "UTF-8").strip
    assert_equal "1.0.3", expected
    assert_equal expected, Master::VERSION
  end

  def test_gemspec_uses_the_same_release_version
    spec = Gem::Specification.load(File.join(Master::ROOT, "master.gemspec"))
    assert_equal Master::VERSION, spec.version.to_s
  end

  def test_constitution_revision_remains_separate
    soul = Master.load_yaml(Master.data_path("soul.yml"))
    assert_equal "2.8.0", soul.fetch("version")
    refute_equal soul.fetch("version"), Master::VERSION
  end
end
