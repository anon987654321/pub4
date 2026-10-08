# frozen_string_literal: true

require "minitest/autorun"
require "yaml"

class TestMusicTheoryCatalog < Minitest::Test
  ROOT = File.expand_path("../..", __dir__)
  PATH = File.join(ROOT, "MASTER", "data", "music_theory", "chords.yml")

  def catalog
    @catalog ||= YAML.safe_load_file(PATH, aliases: false)
  end

  def test_catalog_is_substantially_richer_than_the_old_core
    templates = catalog.fetch("templates")
    assert_operator templates.length, :>=, 70
    assert_operator catalog.fetch("families").values.flatten.uniq.length, :>=, 20
  end

  def test_classic_jazz_and_neosoul_colours_have_interval_data
    templates = catalog.fetch("templates")
    %w[69 m69 maj9 m9 m11 m13 7b5 7b9 7#9 7#11 7alt 13b9 13#11 13sus4].each do |name|
      assert templates.key?(name), "missing chord template #{name}"
      assert templates.fetch(name).is_a?(Array)
      assert_operator templates.fetch(name).length, :>=, 3
    end
  end

  def test_progression_library_contains_real_harmonic_grammars
    progressions = catalog.fetch("progressions")
    %w[ii_v_i ii_v_i_minor backdoor chromatic_mediant minor_descent gospel_69 suspended_cycle].each do |name|
      row = progressions.fetch(name)
      assert_operator row.length, :>=, 3
    end
  end
end
