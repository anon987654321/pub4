# frozen_string_literal: true

require_relative "studio_helper"
require "vips"
require "tmpdir"
require "open3"
require "rbconfig"
require "json"

# What the bare path does, which until 2026-09-23 was nothing: `postpro.rb
# photo.jpg` opened the interactive menu and the path went unread, so anything
# scripted hung on a prompt. The positional is a subject now — one image
# through the same chains --random draws, written beside it — and these shell
# out because ARGV dispatch cannot be exercised in-process: the load guard
# suppresses auto_launch, and the whole point of the change is in auto_launch.
#
# A fixture is generated rather than committed, and small, because a random
# chain is the expensive path in postpro: a 160-pixel frame keeps the suite's
# cost in seconds while still exercising the full chain, sidecar and all.
class TestPostproDispatch < Minitest::Test
  POSTPRO = File.expand_path("../postpro/postpro.rb", __dir__)
  SEED = "4242"

  def run_postpro(dir, *args, env: {})
    Open3.capture2e({ "POSTPRO_SEED" => SEED, "DILLA_QUIET" => "1" }.merge(env),
                    RbConfig.ruby, POSTPRO, *args)
  end

  def frame(dir, name = "frame.jpg")
    path = File.join(dir, name)
    band = (Vips::Image.black(160, 160).cast(:float) + 140).cast(:uchar)
    band.bandjoin([band, band]).write_to_file("#{path}[Q=95]")
    path
  end

  def graded_outputs(dir, name)
    Dir[File.join(dir, "#{File.basename(name, File.extname(name))}_*_v1_*.jpg")]
  end

  # The bare path grades that one image, and --count beside it is honoured
  # rather than read as a second subject ("3" is a count, not a file).
  def test_a_bare_image_is_graded_beside_itself
    Dir.mktmpdir do |dir|
      subject = frame(dir)
      out, status = run_postpro(dir, subject, "--count", "2")
      assert status.success?, "positional grade failed:\n#{out}"
      outputs = graded_outputs(dir, "frame.jpg")
      assert_equal 2, outputs.size, "expected two variations, wrote:\n#{outputs}"

      sidecar = JSON.parse(File.read("#{outputs.first}.json"))
      assert_equal "postpro.chain.v1", sidecar["schema"], "a random chain records itself as a chain"
      assert outputs.none? { |path| path == subject }, "the source is never its own output"
    end
  end

  # A path that exists as neither file nor directory is named and refused; a
  # menu opened on a typo is a hang to anything scripted.
  def test_a_missing_path_is_refused_rather_than_prompted
    Dir.mktmpdir do |dir|
      out, status = run_postpro(dir, File.join(dir, "nope.jpg"))
      refute status.success?, "a missing path must not exit clean"
      assert_includes out, "No such file or directory"
    end
  end

  def test_a_non_image_file_is_refused
    Dir.mktmpdir do |dir|
      notes = File.join(dir, "notes.txt")
      File.write(notes, "not a photograph")
      out, status = run_postpro(dir, notes)
      refute status.success?, "a non-image must not exit clean"
      assert_includes out, "Not an image"
    end
  end

  # A directory subject draws a few random picks from it, the same arm a bare
  # image takes, rather than falling through to the menu.
  def test_a_bare_directory_draws_from_the_folder
    Dir.mktmpdir do |dir|
      frame(dir, "one.jpg")
      out, status = run_postpro(dir, dir, "--count", "1")
      assert status.success?, "positional directory grade failed:\n#{out}"
      assert_equal 1, Dir[File.join(dir, "one_*_v1_*.jpg")].size,
                   "the directory's image should have been graded once:\n#{out}"
    end
  end
end
