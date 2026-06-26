# frozen_string_literal: true

require_relative "../test_helper"

class TestMotionLoraDataset < Minitest::Test
  def setup
    @root = Dir.mktmpdir("motion_lora_dataset")
  end

  def teardown
    FileUtils.rm_rf(@root)
  end

  def test_bootstrap_writes_clips_and_captions
    fake_path = File.join(@root, "fake.mp4")
    File.write(fake_path, "mp4")

    fake_chain = Object.new
    fake_chain.define_singleton_method(:generate) { |**| { path: fake_path } }

    Master::Reach::VideoChain.stub(:generate, fake_chain.method(:generate)) do
      result = Master::Reach::MotionLoraDataset.bootstrap(
        preset: "slow_dolly_push_in",
        subject: "ZIKI girl in neon alley",
        clips: 2,
        root: @root
      )
      assert_equal 2, result[:clips]
      assert Dir.exist?(result[:dir])
      assert File.exist?(File.join(result[:dir], "clip_001.mp4"))
      assert File.exist?(File.join(result[:dir], "captions.json"))
      assert File.exist?(File.join(result[:dir], "caption.txt"))
    end
  end
end