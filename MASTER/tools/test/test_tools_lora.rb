# frozen_string_literal: true

require_relative "tool_test_helper"
require "open3"
require "yaml"

# lora trains on GPUs this suite never has, so what it can check is the part
# that goes wrong without one: the files a run reads, and what gets committed.
class TestLora < Minitest::Test
  LORA = File.join(ToolTest::ROOT, "lora")

  # The origin is public, so a tracked photograph of a subject is a published
  # one. None is tracked, and publishing one is a consent decision that has to
  # be a deliberate edit to this list.
  PUBLISHED_PHOTOGRAPHS = [].freeze

  def test_no_photograph_is_committed_without_being_named_here
    tracked, status = Open3.capture2("git", "-C", ToolTest::ROOT, "ls-files", "--", "lora")
    skip "not a git checkout" unless status.success?

    photos = tracked.lines.map(&:strip).grep(/\.(jpe?g|png|heic|webp)\z/i)
    assert_empty photos - PUBLISHED_PHOTOGRAPHS, "a photograph is committed under lora/ that nobody named"
    assert_empty Dir[File.join(LORA, "johann", "dataset", "*")], "johann has no consented dataset"
  end

  # Written sittings and drawn scenarios go through the one composer preprompt
  # owns, and the drawn set has no file for a glob to find.
  def test_scenarios_are_a_set_that_preprompt_draws
    require_relative "../lora/_toolkit/shoots"

    assert_includes available_sets, "scenarios"
    shoot, prompt = prompts_for("ragnhild", set: "scenarios", only: [3]).first
    assert_equal scenario_sitting(3), shoot
    assert prompt.start_with?("ragnhild, "), prompt
    assert_includes prompt, shoot.fetch("scene")
    assert_equal 50, prompts_for("ragnhild").length, "the written record is untouched"
  end

  # One file holds every written sitting, and best points into it rather than
  # copying prose that would then drift.
  def test_every_written_set_reads_from_ideas_yml
    require_relative "../lora/_toolkit/shoots"

    assert_empty Dir[File.join(LORA, "shoots*.yml")], "a written set outside ideas.yml"
    assert_equal %w[best distance scenarios selfies shoots warp], available_sets
    assert_equal 50, prompts_for("ragnhild", set: "shoots").length
    assert_equal 24, prompts_for("ragnhild", set: "warp").length

    best = prompts_for("ragnhild", set: "best").map(&:first)
    assert_equal (1..24).to_a, best.map { |sitting| sitting["n"] }
    best.each { |sitting| assert_match(/\A(shoots|warp)#\d+\z/, sitting["source"]) }
  end

  def test_selfies_and_the_distance_ladder_are_drawn_sets_with_their_caps
    require_relative "../lora/_toolkit/shoots"

    assert_equal 48, prompts_for("ragnhild", set: "selfies").length
    assert_equal selfie_sitting(60), prompts_for("ragnhild", set: "selfies", only: [60]).first.first
    assert_equal DISTANCE_LADDER.length, prompts_for("ragnhild", set: "distance").length
    assert_empty prompts_for("ragnhild", set: "distance", only: [DISTANCE_LADDER.length + 1])
  end

  # A notebook is written by a lane and then committed, and a token pasted into a
  # cell rides along. The origin is public, so the check reads every tracked
  # notebook, subject.env and config under lora/ for a credential's shape. The
  # failure names the file and line, never the value.
  SECRET_SHAPES = {
    "Replicate token" => /\br8_[A-Za-z0-9]{30,}/,
    "Hugging Face token" => /\bhf_[A-Za-z0-9]{30,}/,
    "OpenAI-style key" => /\bsk-[A-Za-z0-9_-]{20,}/,
    "GitHub token" => /\bgh[pousr]_[A-Za-z0-9]{30,}/,
    "Kaggle key" => /"key"\s*:\s*"[0-9a-f]{32}"/,
    "private key" => /-----BEGIN [A-Z ]*PRIVATE KEY-----/,
  }.freeze

  def secrets_in(text)
    text.each_line.with_index(1).flat_map do |line, number|
      SECRET_SHAPES.filter_map { |name, shape| "#{name} on line #{number}" if line.match?(shape) }
    end
  end

  def test_the_secret_shapes_catch_what_they_name_and_pass_a_placeholder
    assert_equal ["Replicate token on line 1"], secrets_in("REPLICATE_API_TOKEN=r8_#{'a1' * 20}\n")
    assert_equal ["Hugging Face token on line 2"], secrets_in("x\nos.environ['HF_TOKEN'] = 'hf_#{'Z9' * 17}'\n")
    assert_empty secrets_in("HF_TOKEN=hf_yourtoken\nexport HUGGINGFACE_HUB_TOKEN=\"${HF_TOKEN}\"\n")
  end

  def test_no_tracked_notebook_or_subject_file_carries_a_credential
    tracked, status = Open3.capture2("git", "-C", ToolTest::ROOT, "ls-files", "--", "lora")
    skip "not a git checkout" unless status.success?

    files = tracked.lines.map(&:strip).grep(/\.(?:ipynb|env|ya?ml|json|sh)\z|\/lora\z/).reject { |f| f.include?("/dataset/") }
    assert_operator files.length, :>=, 5, "the glob found too few files to have checked anything"
    leaks = files.flat_map { |file| secrets_in(File.read(File.join(ToolTest::ROOT, file))).map { |hit| "#{file}: #{hit}" } }
    assert_empty leaks
  end

  def test_judge_thresholds_load_and_every_one_is_a_number
    thresholds = YAML.safe_load_file(File.join(LORA, "_toolkit", "judge_thresholds.yml")).fetch("thresholds")

    refute_empty thresholds
    thresholds.each { |key, value| assert_kind_of Numeric, value, "#{key} is not a number" }
  end

  def test_every_subject_wrapper_hands_to_run_generate
    wrappers = Dir[File.join(LORA, "*", "lora")].sort
    refute_empty wrappers

    wrappers.each do |path|
      assert_match(%r{exec "\$SUBJECT_DIR/\.\./_toolkit/run_generate\.sh" "\$@"}, File.read(path), path)
    end
  end

  # The grade a subject's samples get is the subject's to name, and portrait
  # when it names none. Read through toolkit.sh itself, on a subject that exists
  # only in a temporary directory.
  def preset_for_subject(env)
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "subject.env"), env)
      out, status = Open3.capture2({ "SUBJECT_DIR" => dir, "POSTPRO_PRESET" => nil },
                                   "sh", "-c", ". \"$1\" && printf %s \"$POSTPRO_PRESET\"", "sh",
                                   File.join(LORA, "_toolkit", "toolkit.sh"))
      assert status.success?
      out
    end
  end

  def test_a_subject_names_its_own_sample_grade_and_defaults_to_portrait
    assert_equal "portrait", preset_for_subject("SUBJECT=probe\nMODEL=probe\n")
    assert_equal "noir", preset_for_subject("SUBJECT=probe\nMODEL=probe\nPOSTPRO_PRESET=noir\n")
  end

  def test_a_sample_already_carrying_this_runs_grade_is_not_graded_again
    load File.join(LORA, "_toolkit", "postpro_samples.rb")
    Dir.mktmpdir do |dir|
      %w[take.jpg take_noir.jpg].each { |name| File.write(File.join(dir, name), "x") }

      assert_equal ["take.jpg"], image_files(Pathname.new(dir), 12, %w[noir]).map { |p| p.basename.to_s }
    end
  end

  # STUDIO/gate.rb parses Ruby only, so a shell script breaks unnoticed.
  def test_every_committed_shell_script_parses
    scripts = (Dir[File.join(LORA, "_toolkit", "*.sh")] + Dir[File.join(LORA, "*", "lora")] +
               Dir[File.join(ToolTest::ROOT, "dilla", "live", "*.sh")]).sort
    refute_empty scripts

    scripts.each do |path|
      shell = File.open(path, &:readline).include?("zsh") ? "zsh" : "sh"
      _out, err, status = Open3.capture3(shell, "-n", path)
      assert status.success?, "#{shell} -n #{path}: #{err}"
    end
  end  # --- curate, on generated frames only ------------------------------------

  def curate_frames(dir)
    require "vips"
    require "tmpdir"
    require_relative "../lora/_toolkit/curate"
    scene = Studio.octave_scene(600, seed: 3)
    paths = {
      "a.jpg" => scene, "a_again.jpg" => (scene * 1.06).cast(:uchar),
      "b.jpg" => Studio.octave_scene(600, seed: 9), "c.jpg" => Studio.octave_scene(600, seed: 17)
    }.map { |name, image| File.join(dir, name).tap { |path| image.write_to_file(path) } }
    Lora::Curate.scan(dir).tap { |candidates| assert_equal paths.length, candidates.length }
  end

  def test_the_curate_report_names_one_moment_chosen_twice
    Dir.mktmpdir do |dir|
      candidates = curate_frames(dir)
      lines = Lora::Curate.report(candidates.map { |c| Lora::Curate.judge(c) }, candidates).join("\n")

      assert_match(/one moment twice — a\.jpg ~ a_again\.jpg/, lines)
      refute_match(/b\.jpg ~/, lines)
    end
  end

  def test_prepare_drops_a_near_duplicate_from_training
    Dir.mktmpdir do |dir|
      candidates = curate_frames(dir)
      dataset = File.join(dir, "out", "dataset")
      written = Lora::Curate.prepare(candidates, into: dataset, token: "probe", short_edge: 512)

      assert_equal 3, written.length, "a.jpg and a_again.jpg are one moment"
      assert_equal 3, Dir[File.join(dataset, "*.jpg")].length
    end
  end

  def test_prepare_holds_every_nth_frame_out_of_the_dataset
    Dir.mktmpdir do |dir|
      candidates = curate_frames(dir)
      dataset = File.join(dir, "out", "dataset")
      holdout = File.join(dir, "out", "holdout")
      written = Lora::Curate.prepare(candidates, into: dataset, token: "probe", short_edge: 512,
                                                 holdout_into: holdout, holdout_every: 2)

      assert_equal 2, written.length
      assert_equal 2, Dir[File.join(dataset, "*.jpg")].length
      assert_equal 2, Dir[File.join(holdout, "*.jpg")].length
      assert_equal 2, Dir[File.join(holdout, "*.txt")].length, "a held frame keeps its caption stub"
      assert_equal candidates.values_at(1, 3), Lora::Curate.split(candidates, holdout_every: 2).last
      assert_equal [candidates, []], Lora::Curate.split(candidates, holdout_every: nil)
    end
  end
end
