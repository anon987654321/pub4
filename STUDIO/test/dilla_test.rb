# frozen_string_literal: true

require "minitest/autorun"
require "json"
require "open3"
require "rbconfig"
require "tmpdir"

# dilla is one Ruby file and one data file. These tests hold the data to the
# shape the engine reads, and run the engine itself on a smoke render, in a
# temporary directory so a test run leaves nothing under the tree.
class DillaTest < Minitest::Test
  DIR = File.expand_path("../dilla", __dir__)
  SCRIPT = File.join(DIR, "dilla.rb")
  DATA = JSON.parse(File.read(File.join(DIR, "dilla.json")))

  def run_dilla(*args, chdir:)
    Open3.capture3(RbConfig.ruby, SCRIPT, *args, chdir:)
  end

  def test_the_tracked_tree_is_the_engine_its_data_and_a_readme
    tracked, status = Open3.capture2("git", "ls-files", ".", chdir: DIR)
    skip "not a git checkout" unless status.success?
    assert_equal %w[.gitignore README.md dilla.json dilla.rb], tracked.lines.map(&:strip).sort
  end

  def test_every_progression_has_chords_a_voicing_for_each_and_a_known_preset
    DATA.fetch("progressions").each do |id, row|
      assert_equal row.fetch("chords").size, row.fetch("freqs").size, "#{id}: a voicing for every chord"
      row.fetch("freqs").each { |voicing| assert(voicing.all?(&:positive?), "#{id}: frequencies are positive") }
      assert_includes DATA.fetch("fx").keys, row.fetch("fx"), "#{id}: its effects preset exists"
      assert row.fetch("tempo").between?(40, 200), "#{id}: a tempo a person can count"
      assert_operator row.fetch("duration"), :>, 0, id
    end
  end

  def test_every_drum_pattern_is_three_rows_of_sixteen_steps
    DATA.fetch("drums").each do |id, pattern|
      assert_equal %w[hat kick snare], pattern.keys.sort, id
      pattern.each_value { |row| assert_equal 16, row.size, id }
    end
  end

  def test_list_names_every_progression_drum_pattern_and_preset
    out, err, status = run_dilla("--list", chdir: Dir.tmpdir)
    assert status.success?, err
    DATA.fetch("progressions").each_key { |id| assert_includes out, id }
    DATA.fetch("drums").each_key { |id| assert_includes out, id }
    DATA.fetch("fx").each_key { |id| assert_includes out, id }
  end

  def test_a_render_is_a_16_bit_mono_wav_of_the_right_length_and_not_silent
    Dir.mktmpdir do |dir|
      id = DATA.fetch("progressions").keys.first
      row = DATA.fetch("progressions").fetch(id)
      path = File.join(dir, "probe.wav")
      _out, err, status = run_dilla("--progression", id, "--drums", DATA.fetch("drums").keys.first, "--out", path, chdir: dir)
      assert status.success?, err
      bytes = File.binread(path)
      assert_equal "RIFF", bytes.byteslice(0, 4)
      assert_equal "WAVE", bytes.byteslice(8, 4)
      channels, rate = bytes.byteslice(22, 2).unpack1("v"), bytes.byteslice(24, 4).unpack1("V")
      assert_equal [1, 44_100], [channels, rate]
      samples = bytes.byteslice(44..).unpack("s<*")
      seconds = samples.size / 44_100.0
      expected = row.fetch("chords").size * row.fetch("duration") * 60.0 / row.fetch("tempo")
      assert_operator seconds, :>=, expected, "at least the chords' own length"
      assert_operator samples.map(&:abs).max, :>, 1000, "the render is not silent"
    end
  end

  def test_quick_renders_the_first_progression_to_out_in_the_working_directory
    Dir.mktmpdir do |dir|
      _out, err, status = run_dilla("--quick", chdir: dir)
      assert status.success?, err
      assert File.file?(File.join(dir, "out", "quick.wav"))
    end
  end

  def test_an_unknown_progression_is_refused
    Dir.mktmpdir do |dir|
      _out, _err, status = run_dilla("--progression", "no_such_progression", "--out", File.join(dir, "x.wav"), chdir: dir)
      refute status.success?
    end
  end
end
