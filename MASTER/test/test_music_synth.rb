# frozen_string_literal: true

require_relative "test_helper"

class TestMusicSynth < Minitest::Test
  def test_writes_valid_wav_for_each_shape
    Dir.mktmpdir do |dir|
      Master::Music::Synth::SHAPES.each do |shape|
        path = File.join(dir, "#{shape}.wav")
        Master::Music::Synth.render(shape:, seconds: 0.02, destination: path)
        assert File.file?(path)
        assert_operator File.size(path), :>, 44
      end
    end
  end

  def test_unknown_shape_is_rejected
    assert_raises(ArgumentError) do
      Master::Music::Synth.render(shape: :purple, destination: "/tmp/never.wav")
    end
  end
end
