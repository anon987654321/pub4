# frozen_string_literal: true

require "minitest/autorun"

class TriangleContractTest < Minitest::Test
  # Minitest::Test has no `test "name" do`; without this Kernel#test swallowed the call
  # and the file never ran.
  def self.test(name, &block) = define_method("test_#{name.gsub(/\W+/, "_")}", &block)

  ROOT = File.expand_path("..", __dir__)

  def source
    @source ||= File.read(File.join(ROOT, "..", "MASTER", "tools", "rails", "triangle.rb"))
  end

  test "triangle derives every surface, master included, from apps.yml" do
    assert_includes source, 'YAML.safe_load_file(File.join(RAILS_ROOT, "apps.yml"))'
    refute_match(/53_?187|38_?\d{3}/, source)
  end

  test "triangle prepares databases and invalidates the development asset manifest before boot" do
    assert_includes source, '"bin/rails", "db:prepare"'
    assert_includes source, 'public", "assets", ".manifest.json"'
    assert_includes source, "clear_asset_manifest(app)"
  end

  test "triangle exposes deterministic named-surface and lifecycle commands" do
    assert_includes source, "def self.selected(names)"
    assert_includes source, 'when nil, "up"'
    assert_includes source, 'when "status"'
    assert_includes source, 'when "down"'
    assert_includes source, "BOOT_TIMEOUT"
  end
end
