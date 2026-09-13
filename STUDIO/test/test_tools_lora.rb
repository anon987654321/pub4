# frozen_string_literal: true

require_relative "studio_helper"
require "open3"
require "yaml"

# lora trains on GPUs this suite never has, so what it can check is the part
# that goes wrong without one: the files a run reads, and what gets committed.
class TestLora < Minitest::Test
  LORA = File.join(Studio::ROOT, "lora")

  # A subject's photographs are published with the repository. Adding one is a
  # consent decision, so it has to be a deliberate edit to this list.
  PUBLISHED_PHOTOGRAPHS = (2..7).map { |n| format("lora/ragnhild/dataset/a_photo_of_ragnhild_%02d.jpg", n) }.freeze

  def test_no_photograph_is_committed_without_being_named_here
    tracked, status = Open3.capture2("git", "-C", Studio::ROOT, "ls-files", "--", "lora")
    skip "not a git checkout" unless status.success?

    photos = tracked.lines.map(&:strip).grep(/\.(jpe?g|png|heic|webp)\z/i)
    assert_empty photos - PUBLISHED_PHOTOGRAPHS, "a photograph is committed under lora/ that nobody named"
    assert_empty Dir[File.join(LORA, "johann", "dataset", "*")], "johann has no consented dataset"
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

  # STUDIO/gate.rb parses Ruby only, so a shell script breaks unnoticed.
  def test_every_committed_shell_script_parses
    scripts = (Dir[File.join(LORA, "_toolkit", "*.sh")] + Dir[File.join(LORA, "*", "lora")] +
               Dir[File.join(Studio::ROOT, "dilla", "live", "*.sh")]).sort
    refute_empty scripts

    scripts.each do |path|
      shell = File.open(path, &:readline).include?("zsh") ? "zsh" : "sh"
      _out, err, status = Open3.capture3(shell, "-n", path)
      assert status.success?, "#{shell} -n #{path}: #{err}"
    end
  end
end
