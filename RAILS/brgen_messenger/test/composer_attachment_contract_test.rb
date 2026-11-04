# frozen_string_literal: true

require "minitest/autorun"

# The server takes a photo or a voice note with no words (Message validates
# content only when nothing is attached); the composer must let one be sent.
# Read from source because the suite has no browser for these controllers.
# The engine's own controllers sit beside this test in the repo and on the box,
# where brgen itself is /home/brgen/app and ../../brgen does not exist.
class ComposerAttachmentContractTest < Minitest::Test
  CONTROLLERS = File.expand_path("../app/javascript/controllers", __dir__)

  def test_send_is_enabled_by_an_attached_file
    source = File.read(File.join(CONTROLLERS, "typing_input_controller.js"))

    assert_match(/addEventListener\("change", this\.onInput\)/, source, "the picker's change re-checks Send")
    assert_match(/input\[type=file\].*files\?\.length > 0/m, source, "a chosen file counts as content")
  end

  # The file field sits beside the recorder's element, not inside it, so a
  # Stimulus target lookup threw on every finished recording.
  def test_the_recorder_fills_the_form_field_and_says_so
    source = File.read(File.join(CONTROLLERS, "voice_recorder_controller.js"))

    refute_match(/this\.fileTarget\.files/, source)
    assert_match(/closest\("form"\)/, source)
    assert_match(/dispatchEvent\(new Event\("change", \{ bubbles: true \}\)\)/, source)
  end
end
