# frozen_string_literal: true

require_relative "test_helper"

class TestPropshaftPaths < Minitest::Test
  def test_excludes_digest_output_directory
    source = File.read(File.join(Master::ROOT, "web", "config", "initializers", "assets.rb"))
    assert_includes source, "excluded_paths"
    assert_includes source, "public", "assets"
  end

  def test_deploy_rc_cleans_nested_assets
    rc = File.read(File.join(Master::ROOT, "..", "DEPLOY", "openbsd", "etc", "rc.d", "master"))
    assert_includes rc, "public/assets/assets"
  end
end