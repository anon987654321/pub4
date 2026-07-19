# frozen_string_literal: true

require_relative "test_helper"

class TestStyleGuides < Minitest::Test
  def test_runtime_style_guides_loads
    data = Master::Ground::RuntimeCatalog.load("style_guides")
    assert_equal "style_guides", data["id"]
    assert data["sources"].is_a?(Array)
    assert data["sources"].any? { |row| row["id"] == "ruby" }
    assert data["sources"].any? { |row| row["id"] == "rails" }
    assert_includes data.dig("gates") || [], "script/style_gate.rb"
  end

  def test_clone_style_guides_script_exists
    path = File.join(Master::ROOT, "script/clone_style_guides.sh")
    assert File.file?(path)
    assert_predicate File.stat(path).mode & 0o111, :positive?, "clone_style_guides.sh should be executable"
  end

  def test_master_rubocop_excludes_web_tree
    config = YAML.safe_load_file(File.join(Master::ROOT, ".rubocop.yml"))
    excludes = Array(config.dig("AllCops", "Exclude"))
    assert_includes excludes, "web/**"
  end

  def test_shared_rescue_handlers_present
    path = File.expand_path("../../RAILS/shared/app/controllers/concerns/shared/rescue_handlers.rb", __dir__)
    skip "OPERATOR not checked out" unless File.file?(path)
    source = File.read(path)
    assert_includes source, "ActiveRecord::RecordNotFound"
    assert_includes source, "ActionController::ParameterMissing"
  end
end