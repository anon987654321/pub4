# frozen_string_literal: true

require "fileutils"
require "json"
require "tmpdir"
require_relative "tools_helper"
ToolTest::Tools.load_tool("postpro/postpro.rb")
require_relative "postpro_fixtures"

# Every render sits beside its source, and nothing moves it.
class TestPostproRendersBesideTheSource < Minitest::Test
  include PostproFixtures

  def test_output_dir_is_the_folder_of_the_source
    Dir.mktmpdir do |dir|
      assert_equal File.expand_path(dir), Postpro::Constitution.output_dir_for(File.join(dir, "frame.jpg"))
    end
  end

  def test_output_dir_ignores_the_output_dir_variable
    Dir.mktmpdir do |dir|
      with_env("POSTPRO_OUTPUT_DIR", File.join(dir, "elsewhere")) do
        assert_equal File.expand_path(dir), Postpro::Constitution.output_dir_for(File.join(dir, "frame.jpg"))
      end
    end
  end

  def test_a_source_inside_the_checkout_renders_in_its_own_folder
    folder = File.join(REPO_ROOT, "STUDIO", "postpro")
    assert_equal folder, Postpro::Constitution.output_dir_for(File.join(folder, "postpro_probe_source.jpg"))
  end

  def test_a_relative_source_resolves_against_the_working_directory
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, "shoot"))
      resolved = Dir.chdir(dir) { File.realpath(Postpro::Constitution.output_dir_for("shoot/frame.jpg")) }
      assert_equal File.join(File.realpath(dir), "shoot"), resolved
    end
  end

  def test_a_source_in_a_folder_with_spaces_keeps_its_folder
    Dir.mktmpdir do |dir|
      folder = File.join(dir, "summer shoot (final)")
      assert_equal folder, Postpro::Constitution.output_dir_for(File.join(folder, "a b.jpg"))
    end
  end

  def test_lut_exports_alone_keep_the_dated_directory
    assert_equal Studio::OutputPaths.render_directory, Postpro::Constitution::OUTPUT_DIR
  end

  def test_the_root_gitignore_keeps_renders_out_of_git_anywhere_in_the_tree
    ignore = File.read(File.join(REPO_ROOT, ".gitignore")).lines.map(&:strip)
    %w[jpg jpeg png webp tif tiff].each do |ext|
      assert_includes ignore, "postpro_*.#{ext}", "renders of .#{ext} sources would be committable"
      assert_includes ignore, "postpro_*.#{ext}.json", "sidecars of .#{ext} renders would be committable"
    end
  end
end

# The constitution's output check holds the same line.
class TestPostproOutputVerification < Minitest::Test
  include PostproFixtures

  def test_a_render_beside_its_source_is_accepted
    Dir.mktmpdir do |dir|
      source = source_in(dir)
      output = File.join(dir, "postpro_frame_01_noir_v1.jpg")
      assert verify_render(source, output)
    end
  end

  def test_a_render_in_another_folder_is_refused
    Dir.mktmpdir do |dir|
      source = source_in(dir)
      output = File.join(dir, "renders", "postpro_frame_v1.jpg")
      error = assert_raises(ArgumentError) { verify_render(source, output) }
      assert_match(/must sit beside its source/, error.message)
    end
  end

  def test_the_output_dir_variable_does_not_license_another_folder
    Dir.mktmpdir do |dir|
      source = source_in(dir)
      elsewhere = File.join(dir, "elsewhere")
      output = File.join(elsewhere, "postpro_frame_v1.jpg")

      with_env("POSTPRO_OUTPUT_DIR", elsewhere) do
        assert_raises(ArgumentError) { verify_render(source, output) }
      end
    end
  end

  def test_a_name_without_the_prefix_is_refused
    Dir.mktmpdir do |dir|
      source = source_in(dir)
      output = File.join(dir, "graded.jpg")
      error = assert_raises(ArgumentError) { verify_render(source, output) }
      assert_match(/postpro_ prefix/, error.message)
    end
  end
end

# A new family retires the old one, and only the old one.
class TestPostproRetiringAFamily < Minitest::Test
  include PostproFixtures

  def test_retiring_removes_only_the_renders_of_that_source
    Dir.mktmpdir do |dir|
      mine = source_in(dir)
      other = source_in(dir, "frame_two.jpg")
      render(dir, "postpro_frame_01_noir_v1.jpg", input: mine)
      render(dir, "postpro_frame_contact.jpg", input: mine)
      render(dir, "postpro_frame_two_01_noir_v1.jpg", input: other)
      File.write(File.join(dir, "postpro_unrelated.jpg"), "no sidecar")

      assert_equal 2, quietly { Postpro::Constitution.retire_previous_renders!(mine) }
      kept = %w[frame.jpg frame_two.jpg postpro_frame_two_01_noir_v1.jpg
                postpro_frame_two_01_noir_v1.jpg.json postpro_unrelated.jpg]
      assert_equal kept, Dir.children(dir).sort
    end
  end

  def test_retiring_survives_a_corrupt_sidecar
    Dir.mktmpdir do |dir|
      mine = source_in(dir)
      broken = File.join(dir, "postpro_broken.jpg.json")
      File.write(broken, "{ not json")

      assert_equal 0, Postpro::Constitution.retire_previous_renders!(mine)
      assert File.exist?(broken)
    end
  end
end

# Which paths a command line names.
class TestPostproCommandLineSubjects < Minitest::Test
  include PostproFixtures

  def test_every_bare_path_is_a_subject
    with_argv("a.jpg", "b.jpg", "c.jpg") { assert_equal %w[a.jpg b.jpg c.jpg], send(:positional_subjects) }
  end

  def test_flag_values_are_not_subjects
    with_argv("--count", "3", "a.jpg", "--preset", "noir") { assert_equal %w[a.jpg], send(:positional_subjects) }
  end

  def test_uplift_is_a_mode_word_not_a_path
    with_argv("--random", "uplift") do
      assert_empty send(:positional_subjects)
      assert_empty send(:random_subjects)
    end
  end

  def test_the_first_subject_is_still_available_alone
    with_argv("a.jpg", "b.jpg") { assert_equal "a.jpg", send(:positional_subject) }
    with_argv("--count", "2") { assert_nil send(:positional_subject) }
  end

  def test_random_takes_its_subject_from_a_trailing_path
    with_argv("--random", "--count", "10", "photo.jpg") { assert_equal %w[photo.jpg], send(:random_subjects) }
  end

  def test_random_takes_its_subject_as_its_own_value_when_it_exists
    Dir.mktmpdir do |dir|
      photo = source_in(dir, "photo.jpg")
      with_argv("--count", "2", "--random", photo) { assert_equal [photo], send(:random_subjects) }
    end
  end

  def test_random_ignores_a_missing_value_and_a_following_flag
    with_argv("--random", "/no/such/photo.jpg") { assert_empty send(:random_subjects) }
    with_argv("--random", "--count", "3") { assert_empty send(:random_subjects) }
    with_argv("--random") { assert_empty send(:random_subjects) }
  end

  def test_random_with_several_paths_keeps_them_all_once
    Dir.mktmpdir do |dir|
      first = source_in(dir, "a.jpg")
      with_argv("--random", first, "b.jpg", "c.jpg") { assert_equal [first, "b.jpg", "c.jpg"], send(:random_subjects) }
    end
  end
end
