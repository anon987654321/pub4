# frozen_string_literal: true

require_relative "tools_helper"
require_relative "postpro_cli_helper"
require "vips"
ToolTest::Tools.load_tool("postpro/postpro.rb")
require "tmpdir"
require "fileutils"
require "open3"
require "rbconfig"
require "json"

# Exercise the actual CLI because ARGV dispatch cannot be exercised in-process:
# the load guard suppresses auto_launch, and the positional path is resolved by
# that entrypoint. Renders land beside their source, so each test's frames sit
# in their own temporary directory and output-path assertions never depend on
# the caller's current directory.
#
# A fixture is generated rather than committed, and small, because a random
# chain is the expensive path in postpro: a 160-pixel frame keeps the suite's
# cost in seconds while still exercising the full chain, sidecar and all.
class TestPostproDispatch < Minitest::Test
  # Each case renders through the CLI, up to ten takes with redraws, so it gets a
  # render budget rather than the 30 s one meant for a hung ffmpeg.
  TIMEOUT = 120

  include PostproCli

  # The bare path grades that one image, and --count beside it is honoured
  # rather than read as a second subject ("3" is a count, not a file).
  def test_a_preset_without_one_shot_paths_fails_fast_instead_of_opening_a_menu
    Dir.mktmpdir do |dir|
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      out, status = run_postpro(dir, "--preset", "fx")
      elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started

      refute status.success?
      assert_includes out, "--input FILE"
      assert_operator elapsed, :<, 5, "invalid named preset mode took #{elapsed.round(2)}s"
    end
  end

  def test_partial_one_shot_flags_fail_fast_instead_of_opening_a_menu
    Dir.mktmpdir do |dir|
      partial_calls = [
        ["--input", File.join(dir, "frame.jpg")],
        ["--output", File.join(dir, "graded.jpg")],
        ["--input", File.join(dir, "frame.jpg"), "--output", File.join(dir, "graded.jpg")],
        ["--input", "--output", "--preset"],
        ["--input", File.join(dir, "frame.jpg"), "--output", "--preset", "portrait"],
        ["--input", File.join(dir, "frame.jpg"), "--output", File.join(dir, "graded.jpg"), "--preset"],
      ]

      partial_calls.each do |args|
        started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        out, status = run_postpro(dir, *args)
        elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started

        refute status.success?, "partial one-shot arguments unexpectedly succeeded: #{args.inspect}"
        assert_includes out, "requires --input FILE, --output FILE and --preset NAME"
        assert_operator elapsed, :<, 5, "invalid invocation took #{elapsed.round(2)}s: #{args.inspect}"
      end
    end
  end

  def test_random_contract_has_five_to_ten_default_variations
    assert_equal(5..10, RANDOM_VARIATIONS)
    refute_empty RANDOM_LANES
  end

  def test_random_chains_keep_a_heavy_analog_substrate
    8.times do |seed|
      chain = random_chain(Random.new(seed))
      analog = chain.map(&:first).map(&:to_s) & Postpro::Constitution::ANALOG_CORE
      assert_operator analog.uniq.length, :>=, 3, "seed #{seed} drifted below analog depth"
    end
  end

  def test_outputs_use_postpro_prefix_beside_the_source
    Dir.mktmpdir do |dir|
      subject = scene(dir)
      out, status = run_postpro(dir, subject, "--count", "2")
      assert status.success?, "prefixed output failed:
#{out}"
      outputs = graded_outputs(dir, "scene.jpg")

      assert_equal 2, outputs.size
      assert outputs.all? { |path| File.dirname(path) == File.dirname(subject) }
      assert outputs.all? { |path| File.basename(path).start_with?("postpro_") }
    end
  end

  def test_a_bare_image_is_graded_beside_itself
    Dir.mktmpdir do |dir|
      subject = scene(dir)
      out, status = run_postpro(dir, subject, "--count", "2")
      assert status.success?, "positional grade failed:\n#{out}"
      outputs = graded_outputs(dir, "scene.jpg")
      assert_equal 2, outputs.size, "expected two variations, wrote:\n#{outputs}"

      sidecar = JSON.parse(File.read("#{outputs.first}.json"))
      assert_equal "postpro.chain.v1", sidecar["schema"], "a random chain records itself as a chain"
      assert outputs.none? { |path| path == subject }, "the source is never its own output"
    end
  end

  # Every render sits beside its source. An output-directory variable in the
  # environment no longer moves it anywhere else.
  def test_output_directory_variable_does_not_move_renders_away_from_the_source
    Dir.mktmpdir do |dir|
      source_dir = File.join(dir, "source")
      elsewhere = File.join(dir, "elsewhere")
      FileUtils.mkdir_p(source_dir)
      subject = frame(source_dir)

      env = { "POSTPRO_OUTPUT_DIR" => elsewhere, "XDG_DATA_HOME" => File.join(dir, "xdg") }
      out, status = run_postpro(dir, subject, "--count", "1", env:)
      assert status.success?, "grade failed:\n#{out}"

      assert_equal 1, graded_outputs(source_dir, "frame.jpg").size,
                   "expected the render beside its source:\n#{out}"
      assert_empty Dir[File.join(elsewhere, "**", "postpro_*")]
      assert_empty Dir[File.join(dir, "xdg", "**", "postpro_*")]
    end
  end

  # --random beside an explicit photograph grades that photograph, not
  # whatever else sits in the downloads folder or the working directory.
  def test_random_with_an_explicit_image_grades_only_that_image
    Dir.mktmpdir do |dir|
      subject = frame(dir, "chosen.jpg")
      frame(dir, "bystander.jpg")

      out, status = run_postpro(dir, "--random", "--count", "1", subject)
      assert status.success?, "random grade failed:\n#{out}"
      assert_equal 1, graded_outputs(dir, "chosen.jpg").size, "the named image was not graded:\n#{out}"
      assert_empty graded_outputs(dir, "bystander.jpg"), "an unnamed image was graded:\n#{out}"

      out, status = run_postpro(dir, "--count", "1", "--random", subject)
      assert status.success?, "random grade with an inline subject failed:\n#{out}"
      assert_empty graded_outputs(dir, "bystander.jpg"), "an unnamed image was graded:\n#{out}"
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
      source_dir = File.join(dir, "source")
      FileUtils.mkdir_p(source_dir)
      frame(source_dir, "one.jpg")

      out, status = run_postpro(dir, source_dir, "--count", "1")
      assert status.success?, "positional directory grade failed:\n#{out}"
      outputs = graded_outputs(source_dir, "one.jpg")
      assert_equal 1, outputs.size,
                   "the directory's image should have been graded once, beside itself:\n#{out}"
    end
  end
end
