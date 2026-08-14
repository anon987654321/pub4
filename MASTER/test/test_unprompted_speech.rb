# frozen_string_literal: true

require "minitest/autorun"

# MASTER speaks when spoken to and listens when asked, and nothing in the boot
# path decides either for the visitor.
#
# face_loops_nudge.js already carries this scar in its own header: "Fourth
# instance of the unprompted-blurting class in this file's history (spoken
# 'scanning' filler, the 'still here' idle nudge, the STT-hears-its-own-TTS echo
# loop); the previous three were silenced too." Each was fixed where it was
# found, and the class came back somewhere else. This is the gate the fourth fix
# did not get.
#
# The fifth was the welcome greeting, and it was the worst of them because it
# did not look like blurting. startEverything() sent WELCOME_GREETING_PROMPT --
# "Introduce yourself to a new visitor... you are the world's first AI built
# entirely in pure Ruby..." -- as a real chat turn, 700ms after every page load.
# Autostart meant that was load time rather than after a human tap, the web
# session is process-global so the instruction landed in whatever conversation
# was already running, and being a real turn it stayed in history and kept the
# model introducing itself afterwards. Measured on the live face 2026-08-14:
# "my name is Johann, remember it" was answered with that pitch nearly verbatim.
class TestUnpromptedSpeech < Minitest::Test
  PUBLIC = File.expand_path("../web/public", __dir__)

  def read(name) = File.read(File.join(PUBLIC, name), encoding: "UTF-8")

  # The generated runtime, not just the part file: the boot path that actually
  # ships is the concatenation, and the two have drifted before.
  def boot_sources = { "face.part5.txt" => read("face.part5.txt"), "face.runtime.js" => read("face.runtime.js") }

  def code_of(source)
    source.lines.reject { |line| line.strip.start_with?("//") }.join
  end

  def test_nothing_sends_a_greeting_prompt_on_boot
    boot_sources.each do |name, source|
      code = code_of(source)

      refute_includes code, "WELCOME_GREETING_PROMPT",
                      "#{name}: a welcome-greeting prompt is back in the boot path"
      refute_includes code, "sendWelcomeGreeting",
                      "#{name}: something still calls sendWelcomeGreeting on boot"
      refute_match(/Introduce yourself/i, code,
                   "#{name}: the boot path tells the model to introduce itself")
    end
  end

  # The specific pitch, wherever it tries to reappear. Naming it is the point:
  # this is the sentence people actually complained about.
  def test_no_face_asset_scripts_the_pure_ruby_pitch
    Dir[File.join(PUBLIC, "*.js"), File.join(PUBLIC, "face.part*.txt")].sort.each do |path|
      code = code_of(File.read(path, encoding: "UTF-8"))

      refute_match(/world's first AI/i, code, "#{File.basename(path)} scripts the self-introduction again")
    end
  end

  # Idle nudges must stay opt-in, and opt-in means no timer at all by default —
  # not a timer that checks a flag, which is how the previous three came back.
  # The speech timer specifically, not the first setInterval in the file — the
  # research refill is also a timer, sits earlier, and is separately gated. An
  # assertion that could not tell them apart failed on correct code, which is a
  # checker wrong in the direction that gets it deleted.
  def test_idle_nudges_arm_no_speech_timer_unless_explicitly_enabled
    source = read("face_loops_nudge.js")
    guard = source[/if \(!nudgesEnabled\(\)\) return[^\n]*/]
    speech_timer = source.index(", NUDGE_INTERVAL_MS)")

    refute_nil guard, "face_loops_nudge.js no longer returns early when nudges are off"
    refute_nil speech_timer, "the nudge speech timer is no longer recognisable — re-derive this test"
    assert_operator source.index(guard), :<, speech_timer,
      "the speech timer is created before the enabled check — the default page now wakes up to consider speaking"
  end

  # The other timer in the file fetches research lines. It must be gated too, or
  # a page with nudges off still talks to the server on a ten-minute clock.
  def test_the_research_refill_timer_is_also_gated
    source = read("face_loops_nudge.js")
    refill = source[/if \(RESEARCH_NUDGES && nudgesEnabled\(\)\) \{[^}]*\}/m]

    refute_nil refill, "the research refill timer is no longer behind nudgesEnabled()"
    assert_includes refill, "setInterval(_refillResearch"
  end

  def test_nudges_are_off_by_default
    source = read("face_loops_nudge.js")

    assert_match(/localStorage\.getItem\('master:idle-nudges'\) === '1'/, source)
    assert_match(/return false;\n\s*\}\n\s*const NUDGE_INTERVAL_MS/, source,
                 "nudgesEnabled() should fall through to false when no preference is set")
  end

  # The other half of "only when asked": the microphone.
  #
  # voiceAutoEnabled() read `!== '0'`, so a visitor with no stored preference got
  # true and maybeAutoVoice() opened the mic 1.2s after load. The comment above it
  # justified that as happening "after the primer tap (a real user gesture that
  # also unlocks audio)" — and autostart had deleted the primer tap. Same defect
  # as the greeting: autostart invalidated a premise and nothing rechecked it.
  #
  # The pref itself is fine and stays. enterVoiceMode() sets it on a deliberate
  # entry, exitVoiceMode() clears it on a deliberate exit; it is a memory of a
  # choice. It was only ever wrong about what to assume before a choice was made.
  def test_voice_mode_does_not_arm_itself_before_the_visitor_has_chosen_it
    boot_sources.each do |name, source|
      read_pref = source[/localStorage\.getItem\('master:voice-auto'\)[^\n;]*/]

      refute_nil read_pref, "#{name}: the voice-auto preference is no longer read here"
      assert_includes read_pref, "=== '1'",
                      "#{name}: absent means yes again — a first-time visitor gets the mic opened for them"
    end
  end

  # The memory of a deliberate choice must survive, or the fix above turns
  # hands-free from a default into something unreachable.
  def test_a_deliberate_entry_still_opts_in_for_next_time
    source = read("face.part5.txt")

    assert_match(/if \(!opts\.fromAuto\) setVoiceAuto\(true\);/, source,
                 "deliberate voice-mode entry no longer remembers the choice")
    assert_match(/if \(opts\.reason !== 'unreliable'\) setVoiceAuto\(false\);/, source,
                 "deliberate voice-mode exit no longer clears the choice")
  end

  # The ambient loop may play. It may not talk.
  def test_the_music_loop_does_not_speak
    source = read("face_loops_music.js")
    code = code_of(source)

    refute_includes code, "PICKUP_LINES", "the music loop is scripting pick-up lines again"
    refute_match(/setInterval\(\s*speakPickup/, code, "the music loop speaks on a timer again")
    refute_match(/enqueueSpeech|announceTTS|MASTER_FACE\?\.speak/, code,
                 "the music loop reaches a speech path — it is background audio, not a speaker")
  end
end
