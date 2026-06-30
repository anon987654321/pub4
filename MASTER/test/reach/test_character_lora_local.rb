# frozen_string_literal: true

require "fileutils"
require "json"
require_relative "../test_helper"

class TestCharacterLoraLocal < Minitest::Test
  def setup
    @root = File.join(Dir.tmpdir, "char_lora_local_#{Process.pid}")
    @train_dir = File.join(@root, "train")
    FileUtils.mkdir_p(@root)
    paths = []
    2.times do |index|
      paths << File.join(@root, "src_#{index}.jpg")
      File.write(paths.last, "x" * 30_000)
    end
    Master::Reach::CharacterLoraLocal.prepare_dataset(paths, @train_dir, trigger_word: "zikigirl")
  end

  def teardown
    FileUtils.rm_rf(@root)
  end

  def test_bootstrap_writes_dataset_config_and_run_script
    result = Master::Reach::CharacterLoraLocal.bootstrap(
      name: "zikigirl",
      train_dir: @train_dir,
      out_dir: @root,
      trigger_word: "zikigirl",
      ai_toolkit_root: "/tmp/ai-toolkit"
    )
    assert_equal :local, result[:mode]
    assert_equal 2, result[:images]
    assert File.exist?(result[:config_path])
    assert File.executable?(result[:run_script])
    assert_equal 2, Dir.glob(File.join(result[:train_dir], "*.jpg")).size
    assert_equal 2, Dir.glob(File.join(result[:train_dir], "*.txt")).size
    caption = File.read(Dir.glob(File.join(result[:train_dir], "*.txt")).first)
    assert_includes caption, "zikigirl"
    assert_includes caption, "realistic skin texture"
    config = File.read(result[:config_path])
    assert_includes config, "trigger_word: \"zikigirl\""
    assert_includes config, "linear: 32"
    assert_includes config, result[:train_dir]
    run_script = File.read(result[:run_script])
    assert_includes run_script, "config/ai_toolkit.yaml"
    assert_operator run_script.scan(/^fi$/).size, :>=, 3
  end
end
