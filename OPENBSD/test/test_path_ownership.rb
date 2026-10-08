# frozen_string_literal: true

require "minitest/autorun"
require "yaml"
require_relative "../lib/utf8"

# PATH_OWNERSHIP.yml had no reader, and so it named `openbsd/sh/vps_ci.sh`, an
# `archive/` that does not exist and lowercase `rails/` paths for months while
# omitting most of the tree. These three assertions are what keep a map honest:
# every key names something, everything is named, and every check can run.
class PathOwnershipTest < Minitest::Test
  OPENBSD = File.expand_path("..", __dir__)
  REPO = File.expand_path("..", OPENBSD)
  MAP = File.join(OPENBSD, "PATH_OWNERSHIP.yml")

  def ownership
    @ownership ||= YAML.safe_load_file(MAP).fetch("ownership")
  end

  def matches(key)
    Dir.glob(File.join(OPENBSD, key.delete_suffix("/")), File::FNM_DOTMATCH)
  end

  def test_every_key_names_a_path_that_exists
    dead = ownership.keys.select { |key| matches(key).empty? }
    assert_empty dead, "PATH_OWNERSHIP.yml keys that name nothing"
  end

  def test_every_top_level_entry_has_an_owner
    covered = ownership.keys.flat_map { |key| matches(key) }.map { |path| File.expand_path(path) }
    orphans = Dir.children(OPENBSD).reject { |entry| entry.start_with?(".") }.reject do |entry|
      covered.include?(File.join(OPENBSD, entry))
    end
    assert_empty orphans.sort, "top-level OPENBSD entries with no PATH_OWNERSHIP.yml key"
  end

  def test_every_check_names_files_that_exist
    missing = ownership.flat_map do |key, row|
      row.fetch("check").to_s.scan(%r{\b(?:OPENBSD|MASTER|RAILS)/[\w./-]+}).reject do |path|
        File.exist?(File.join(REPO, path))
      end.map { |path| "#{key}: #{path}" }
    end
    assert_empty missing, "checks naming files that are gone"
  end

  def test_every_row_declares_purpose_risk_and_check
    incomplete = ownership.reject { |_, row| row.is_a?(Hash) && (%w[purpose risk check] - row.keys).empty? }
    assert_empty incomplete.keys
  end
end
