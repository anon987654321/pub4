# frozen_string_literal: true

require_relative "tool_test_helper"
require "vips"
require "tmpdir"
require_relative "../postpro/lib/frame_set"

# A set reading is only worth its known cases. Near-duplicates: the same frame
# brighter, recompressed or trimmed at the edges is one photograph, and a frame
# built from different noise is another. Exposure: a frame a stop above its
# siblings reads as a stop above them.
class TestFrameSet < Minitest::Test
  SIZE = 512

  def scene(seed) = Studio.octave_scene(SIZE, seed:)

  def write(dir, name:, image:)
    File.join(dir, name).tap { |path| image.write_to_file(path) }
  end

  def distance(one, other)
    Postpro::FrameSet.distance(Postpro::FrameSet.fingerprint(one), Postpro::FrameSet.fingerprint(other))
  end

  def test_the_same_frame_brighter_or_recompressed_is_one_photograph
    original = scene(1)
    brighter = (original * 1.08).cast(:uchar)
    recompressed = Vips::Image.new_from_buffer(original.jpegsave_buffer(Q: 60), "")

    assert_operator distance(original, brighter), :<=, Postpro::FrameSet::NEAR
    assert_operator distance(original, recompressed), :<=, Postpro::FrameSet::NEAR
  end

  def test_a_different_frame_is_a_different_photograph
    assert_operator distance(scene(1), scene(2)), :>, Postpro::FrameSet::NEAR * 1.5,
                    "an unrelated frame has to read well clear of the duplicate line"
  end

  def test_near_duplicates_names_the_pair_and_not_the_stranger
    Dir.mktmpdir do |dir|
      original = write(dir, name: "a.png", image: scene(1))
      repeat = write(dir, name: "b.png", image: (scene(1) * 1.05).cast(:uchar))
      stranger = write(dir, name: "c.png", image: scene(2))

      pairs = Postpro::FrameSet.near_duplicates([original, repeat, stranger])
      assert_equal [[original, repeat]], pairs.map { |pair| [pair.first, pair.second] }
    end
  end

  # A stop is a doubling of light. Coded 89 decodes to 0.0999 linear and coded
  # 125 to 0.2051, a hair over double, so the brighter frame reads one stop above
  # its two siblings and they read zero.
  def test_a_frame_a_stop_brighter_reads_one_stop_above_the_set
    Dir.mktmpdir do |dir|
      grey = ->(name, level) { write(dir, name:, image: (Vips::Image.black(64, 64) + level).cast(:uchar)) }
      paths = [grey.call("a.png", 89), grey.call("b.png", 89), grey.call("c.png", 125)]

      offsets = Postpro::FrameSet.exposure_offsets(paths)
      assert_in_delta 0.0, offsets[paths[0]], 0.01
      assert_in_delta 1.0, offsets[paths[2]], 0.05, "double the light is one stop"
    end
  end

  def test_frames_finds_images_and_ignores_the_rest
    Dir.mktmpdir do |dir|
      %w[b.JPG a.png notes.txt c.webp].each { |name| File.write(File.join(dir, name), "") }
      assert_equal %w[a.png b.JPG c.webp], Postpro::FrameSet.frames(dir).map { |path| File.basename(path) }
    end
  end
end
