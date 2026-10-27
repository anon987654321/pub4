# frozen_string_literal: true

require_relative "tools_helper"
ToolTest::Tools.load_tool("postpro/postpro.rb")
require_relative "postpro_cli_helper"

# A run's family of takes, end to end through the CLI: how they are named,
# what their sidecars say, the contact sheet, several subjects at once, and
# where every render lands.
class TestPostproFamilies < Minitest::Test
  include PostproCli
  # Each case renders through the CLI, up to ten takes with redraws, so it gets a
  # render budget rather than the 30 s one meant for a hung ffmpeg.
  TIMEOUT = 120


  # Naming and the family.

  def test_takes_are_numbered_in_draw_order_and_never_collide
    Dir.mktmpdir do |dir|
      graded!(dir, scene(dir), "--count", "3")
      names = family(dir, "scene.jpg").map { |path| File.basename(path) }

      assert_equal 3, names.size
      assert names.all? { |name| name.match?(/\Apostpro_scene_\d\d_[a-z0-9_]+_v1\.jpg\z/) }, names.inspect
      assert_equal %w[01 02 03], take_numbers(names)
    end
  end

  def test_no_take_falls_back_to_a_timestamped_name
    Dir.mktmpdir do |dir|
      graded!(dir, scene(dir), "--count", "3")
      assert_empty Dir[File.join(dir, "postpro_*_v1_*T*Z*.jpg")]
    end
  end

  def test_take_sidecars_name_their_take
    Dir.mktmpdir do |dir|
      graded!(dir, scene(dir), "--count", "3")
      paths = family(dir, "scene.jpg")
      assert_equal take_numbers(paths).map(&:to_i), sidecars(paths).map { |data| data["take"] }
    end
  end

  def test_take_sidecars_name_a_heavy_look_and_the_dealt_lane
    Dir.mktmpdir do |dir|
      graded!(dir, scene(dir), "--heavy", "--count", "3")
      sidecars(family(dir, "scene.jpg")).each do |data|
        assert_includes HEAVY_LOOKS.map(&:to_s), data["look"]
        assert_equal HEAVY_LANE_DEAL[data["take"] - 1].to_s, data["lane"]
      end
    end
  end

  def test_a_take_name_matches_its_sidecar
    Dir.mktmpdir do |dir|
      graded!(dir, scene(dir), "--heavy", "--count", "2")
      family(dir, "scene.jpg").zip(sidecars(family(dir, "scene.jpg"))).each do |path, data|
        assert_includes File.basename(path), "_#{data["look"]}_#{data["lane"]}_v1"
      end
    end
  end

  def test_a_family_never_repeats_a_look
    Dir.mktmpdir do |dir|
      graded!(dir, scene(dir), "--heavy", "--count", "4")
      looks = sidecars(family(dir, "scene.jpg")).map { |data| data["look"] }
      assert_operator looks.size, :>=, 2
      assert_equal looks.uniq, looks
    end
  end

  def test_a_bare_run_makes_ten_takes
    Dir.mktmpdir do |dir|
      out = graded!(dir, scene(dir))
      assert_includes out, "variations=10"
      assert_operator family(dir, "scene.jpg").size, :>=, 6, "most of ten takes should survive:\n#{out}"
    end
  end

  def test_a_bare_run_writes_a_contact_sheet_of_its_takes
    Dir.mktmpdir do |dir|
      graded!(dir, scene(dir), "--count", "3")
      sheet = contact_sheet(dir, "scene.jpg")
      listed = JSON.parse(File.read("#{sheet}.json"))["takes"].map { |entry| entry["file"] }
      assert_equal family(dir, "scene.jpg").map { |path| File.basename(path) }, listed
    end
  end

  def test_a_single_take_run_writes_no_contact_sheet
    Dir.mktmpdir do |dir|
      graded!(dir, scene(dir), "--count", "1")
      refute File.exist?(contact_sheet(dir, "scene.jpg"))
    end
  end

  def test_the_contact_sheet_can_be_switched_off
    Dir.mktmpdir do |dir|
      graded!(dir, scene(dir), "--count", "2", env: { "POSTPRO_CONTACT" => "0" })
      refute File.exist?(contact_sheet(dir, "scene.jpg"))
    end
  end

  def test_a_second_run_replaces_the_first_family
    Dir.mktmpdir do |dir|
      subject = scene(dir)
      graded!(dir, subject, "--count", "2", env: { "POSTPRO_SEED" => "100" })
      graded!(dir, subject, "--count", "2", env: { "POSTPRO_SEED" => "101" })
      seeds = Dir[File.join(dir, "postpro_*.json")].map { |path| JSON.parse(File.read(path))["seed"] }
      assert_equal [101], seeds.uniq, "the first run's renders should have been retired"
    end
  end

  def test_the_same_seed_draws_the_same_family
    chains = 2.times.map do
      Dir.mktmpdir do |dir|
        graded!(dir, scene(dir), "--count", "2")
        sidecars(family(dir, "scene.jpg")).map { |data| data.values_at("look", "chain") }
      end
    end

    refute_empty chains.first
    assert_equal chains.first, chains.last
  end

  # Several subjects.

  def test_several_images_each_get_their_own_family_beside_them
    Dir.mktmpdir do |dir|
      one, two = %w[one two].map { |name| File.join(dir, name).tap { |path| FileUtils.mkdir_p(path) } }
      graded!(dir, scene(one, "a.jpg"), scene(two, "b.jpg"), "--count", "2")

      refute_empty family(one, "a.jpg")
      refute_empty family(two, "b.jpg")
      assert_empty Dir[File.join(one, "postpro_b_*")] + Dir[File.join(two, "postpro_a_*")]
    end
  end

  def test_random_with_several_images_grades_each_of_them
    Dir.mktmpdir do |dir|
      graded!(dir, "--random", scene(dir, "a.jpg"), scene(dir, "b.jpg"), "--count", "1")
      assert_equal [1, 1], [family(dir, "a.jpg").size, family(dir, "b.jpg").size]
    end
  end

  def test_one_bad_path_refuses_the_whole_batch_before_rendering
    Dir.mktmpdir do |dir|
      out, status = run_postpro(dir, scene(dir, "good.jpg"), File.join(dir, "missing.jpg"), "--count", "1")
      refute status.success?
      assert_includes out, "No such file or directory"
      assert_empty Dir[File.join(dir, "postpro_*")], "nothing should render when the batch is refused"
    end
  end

  def test_a_non_image_among_images_refuses_the_batch
    Dir.mktmpdir do |dir|
      notes = File.join(dir, "notes.txt")
      File.write(notes, "words")
      out, status = run_postpro(dir, "--random", scene(dir, "good.jpg"), notes, "--count", "1")

      refute status.success?
      assert_includes out, "Not an image"
      assert_empty Dir[File.join(dir, "postpro_*")]
    end
  end

  # Where renders land.

  def test_a_relative_subject_renders_beside_it
    Dir.mktmpdir do |dir|
      shoot = File.join(dir, "shoot")
      FileUtils.mkdir_p(shoot)
      scene(shoot)

      graded!(dir, "shoot/scene.jpg", "--count", "1")
      assert_equal 1, family(shoot, "scene.jpg").size
      assert_empty Dir[File.join(dir, "postpro_*")]
    end
  end

  def test_a_folder_with_spaces_keeps_its_renders
    Dir.mktmpdir do |dir|
      folder = File.join(dir, "summer shoot")
      FileUtils.mkdir_p(folder)
      graded!(dir, scene(folder, "a frame.jpg"), "--count", "1")
      assert_equal 1, Dir[File.join(folder, "postpro_a_frame_01_*_v1.jpg")].size
    end
  end

  def test_random_with_a_folder_renders_beside_each_nested_image
    Dir.mktmpdir do |dir|
      day, night = %w[day night].map { |name| File.join(dir, "set", name).tap { |path| FileUtils.mkdir_p(path) } }
      scene(day, "d.jpg")
      scene(night, "n.jpg")
      graded!(dir, "--random", File.join(dir, "set"), "--count", "1")
      assert_equal [1, 1], [family(day, "d.jpg").size, family(night, "n.jpg").size]
    end
  end

  def test_the_output_dir_variable_moves_nothing_for_random_runs
    Dir.mktmpdir do |dir|
      elsewhere = File.join(dir, "elsewhere")
      graded!(dir, "--random", scene(dir), "--count", "1", env: { "POSTPRO_OUTPUT_DIR" => elsewhere })
      assert_equal 1, family(dir, "scene.jpg").size
      assert_empty Dir[File.join(elsewhere, "**", "*")]
    end
  end

  def test_an_explicit_one_shot_output_is_written_where_it_is_named
    Dir.mktmpdir do |dir|
      target = File.join(dir, "published", "hero.jpg")
      FileUtils.mkdir_p(File.dirname(target))
      graded!(dir, "--input", scene(dir), "--output", target, "--preset", "portrait")
      assert File.exist?(target)
    end
  end
end
