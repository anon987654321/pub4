# frozen_string_literal: true

require_relative "test_helper"

class TestPropshaftPaths < Minitest::Test
  def test_excludes_digest_output_directory
    app_rb = File.read(File.join(Master::ROOT, "web", "config", "application.rb"))
    safety = File.read(File.join(Master::ROOT, "web", "config", "initializers", "propshaft_safety.rb"))
    assert_includes app_rb, "excluded_paths"
    assert_includes app_rb, "public", "assets"
    assert_includes safety, '"assets", "assets"'
  end

  def test_deploy_rc_cleans_nested_assets
    rc = File.read(File.join(Master::ROOT, "..", "OPENBSD", "etc", "rc.d", "master"))
    assert_includes rc, "public/assets/assets"
    assert_includes rc, "assets:precompile"
  end
end
