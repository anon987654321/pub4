# frozen_string_literal: true

require "minitest/autorun"

class CliFaceContractTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)

  def read(path)
    File.read(File.join(ROOT, path))
  end

  def test_terminal_face_declares_supported_state_vocabulary
    face = read("lib/cli/face.rb")
    laws = read("data/laws.yml")

    %w[idle listening thinking working speaking warning error sleeping ready].each do |state|
      assert_includes face, state
    end

    assert_match(/STATES\s*=\s*%i\[idle listening thinking working speaking warning error sleeping ready\]/, face)
    assert_match(/terminal_law_ring:\s*true/, laws)
  end

  def test_terminal_face_does_not_direct_voice_users_to_press_enter
    window = read("lib/cli/face/window.rb")
    refute_match(/listening[^\n]*enter to stop/i, window)
    assert_match(/listening[^\n]*say stop or type to interrupt/i, window)
  end
end
