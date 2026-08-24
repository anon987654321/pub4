# frozen_string_literal: true

require "minitest/autorun"
require "pathname"
require "yaml"
require_relative "../../app/services/shared/demo_media"

class DemoMediaTest < Minitest::Test
  CATALOG = Pathname.new(__dir__).join("../../../brgen/config/demo_media/bergen.yml").expand_path

  def test_skip_attach_when_env_flag_set
    refute Shared::DemoMedia.skip_attach? unless ENV["SKIP_DEMO_MEDIA"]
  end

  def test_skip_attach_with_env_override
    with_env("SKIP_DEMO_MEDIA" => "1") do
      assert Shared::DemoMedia.skip_attach?
    end
  end

  def test_catalog_resolves_bergen_seed_urls
    skip "bergen catalog missing" unless CATALOG.file?

    entry = Shared::DemoMedia::Catalog.resolve("bergen-floyen-morning", catalog: CATALOG)
    assert entry
    assert_match(%r{upload\.wikimedia\.org}, entry["url"])
  end

  def test_bergen_catalog_lists_core_post_seeds
    skip "bergen catalog missing" unless CATALOG.file?

    images = YAML.safe_load_file(CATALOG, permitted_classes: [], aliases: true).fetch("images", {})
    %w[bergen-floyen-morning bergen-bryggen-rain bergen-fish-market bergen-place-bryggen].each do |seed|
      assert images.key?(seed), "missing catalog seed #{seed}"
    end
  end

  private

  def with_env(overrides)
    backup = overrides.keys.to_h { |key| [ key, ENV[key] ] }
    overrides.each { |key, value| ENV[key] = value }
    yield
  ensure
    backup.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
  end
end
