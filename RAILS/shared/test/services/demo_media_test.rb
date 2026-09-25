# frozen_string_literal: true

require "minitest/autorun"
require "pathname"
require "tmpdir"
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
    if entry["file"]
      assert Shared::DemoMedia::Catalog.file_path(entry["file"], catalog: CATALOG), "#{entry['file']} is not on disk"
    else
      assert_match(%r{upload\.wikimedia\.org}, entry["url"])
    end
  end

  # Every file row names a frame that ships with the app, so a seed on the box
  # attaches it instead of falling through to picsum.
  def test_every_catalog_file_is_on_disk
    skip "bergen catalog missing" unless CATALOG.file?

    images = YAML.safe_load_file(CATALOG, permitted_classes: [], aliases: true).fetch("images", {})
    missing = images.filter_map { |key, row| key if row.is_a?(Hash) && row["file"] && !CATALOG.dirname.join(row["file"]).file? }
    assert_empty missing
  end

  def test_missing_file_is_skipped_not_raised
    require "active_support/core_ext/object/blank"
    Dir.mktmpdir do |dir|
      catalog = File.join(dir, "demo.yml")
      File.write(catalog, { "images" => { "gone" => { "file" => "images/gone.jpg" } } }.to_yaml)
      record = Object.new
      _out, err = capture_io do
        refute Shared::DemoMedia.attach_from_catalog!(record, :photo, seed: "gone", catalog:)
      end
      assert_match(/not on disk/, err)
    end
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
