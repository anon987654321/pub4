# frozen_string_literal: true

require "minitest/autorun"

class TriangleContractTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)

  def source
    @source ||= File.read(File.join(ROOT, "bin", "triangle"))
  end

  test "triangle derives app surfaces from apps.yml and keeps master explicit" do
    assert_includes source, 'YAML.safe_load_file(File.join(RAILS_ROOT, "apps.yml"))'
    assert_includes source, 'name: "master", port: 53187'
    refute_match(/port:\s*38\d{3}/, source)
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
