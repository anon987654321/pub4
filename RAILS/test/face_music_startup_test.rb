# frozen_string_literal: true

require "minitest/autorun"

class FaceMusicStartupTest < Minitest::Test
  RAILS_ROOT = File.expand_path("..", __dir__)
  MUSIC_PATH = File.join(RAILS_ROOT, "master", "public", "face_loops_music.js")
  ACTIONS_PATH = File.join(RAILS_ROOT, "master", "public", "chat_actions.js")

  def music_source = File.read(MUSIC_PATH)
  def actions_source = File.read(ACTIONS_PATH)

  def test_background_music_does_not_start_automatically
    source = music_source

    refute_includes source, "__ambientArmed"
    assert_equal 0, source.scan(/window\._faceMusic\.start\s*\(/).length
    refute_match(/setTimeout\s*\([^;]*window\._faceMusic\.start\s*\(/m, source)
  end

  def test_explicit_music_controls_still_work
    assert_match(/toggle:\s*\(artist\)\s*=>\s*\(playing\s*\?\s*stop\(\)\s*:\s*start\(artist\)\)/,
                 music_source)
    assert_includes actions_source, "window._faceMusic?.toggle?.();"
    assert_includes actions_source, "if (data.stop) window._faceMusic?.stop?.();"
    assert_includes actions_source, "else if (data.artist) window._faceMusic?.setArtist?.(String(data.artist));"
  end
end
