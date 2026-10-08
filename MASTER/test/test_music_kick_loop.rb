# frozen_string_literal: true

require_relative "test_helper"

class TestMusicKickLoop < Minitest::Test
  def test_writes_valid_looping_wav
    Dir.mktmpdir do |dir|
      path = File.join(dir, "kick.wav")

      result = Master::Music::KickLoop.render(destination: path)

      assert_equal path, result
      assert File.file?(path)
      assert_operator File.size(path), :>, 44

      header = File.binread(path, 44)
      assert_equal "RIFF", header[0, 4]
      assert_equal "WAVE", header[8, 4]
      assert_operator header[40, 4].unpack1("V"), :>, 0
    end
  end

  def test_techno_kick_intent_reaches_kick_loop
    assert Master::Io::MediaIntent.handles?("generate a looping hard hitting techno kick")

    seen = nil
    captured_path = nil
    Master::Music::KickLoop.stub(:render, ->(destination:) { seen = destination; destination }) do
      result = Master::Io::MediaIntent.dispatch("generate a looping hard hitting techno kick")
      assert result.ok?
      captured_path = result.value[:path]
      assert_match(%r{/master-techno-kick-.*\.wav\z}, captured_path)
    end
    assert_equal captured_path, seen
  end
end
