# frozen_string_literal: true

require "minitest/autorun"
require "open3"
require "json"
require "tmpdir"
require "rbconfig"
require_relative "../dilla/dilla"

class DillaSoundFxTest < Minitest::Test
  DIR = File.expand_path("../dilla", __dir__)
  SCRIPT = File.join(DIR, "dilla.rb")
  SOUND_DATA = JSON.parse(File.read(File.join(DIR, "data", "sound_fx.json")))
  ENGINE_DATA = JSON.parse(File.read(File.join(DIR, "data", "dilla.json")))
  EVENTS = Dilla::SoundFx::EVENTS

  def test_manifest_has_exact_lifecycle_coverage_and_bounded_levels
    assert_equal EVENTS.sort, SOUND_DATA.fetch("events").keys.sort
    assert_equal 1, SOUND_DATA.fetch("schema")
    assert_operator SOUND_DATA.fetch("target_peak_dbfs"), :<=, -6.0
    assert_operator SOUND_DATA.fetch("target_peak_dbfs"), :>=, -24.0
    EVENTS.each do |event|
      frame = Dilla::SoundFx.render(event, sound_data: SOUND_DATA, engine_data: ENGINE_DATA, seed: 23)
      assert_equal 2, frame.length, event
      refute_empty frame.first, event
      assert frame.flatten.all?(&:finite?), "#{event}: non-finite sample"
      peak = frame.flatten.map(&:abs).max
      assert_operator peak, :>, 0.1, "#{event}: unexpectedly silent"
      assert_operator peak, :<=, (10.0**(SOUND_DATA.fetch("target_peak_dbfs") / 20.0)) + 1e-8, event
      assert_operator frame.first.size, :<=, 3 * 44_100, event
    end
  end

  def test_same_event_and_seed_render_identically
    first = Dilla::SoundFx.render("complete", sound_data: SOUND_DATA, engine_data: ENGINE_DATA, seed: 1984)
    second = Dilla::SoundFx.render("complete", sound_data: SOUND_DATA, engine_data: ENGINE_DATA, seed: 1984)
    assert_equal first, second
  end

  def test_player_resolution_ignores_relative_path_entries
    Dir.mktmpdir("dilla-fx-player-") do |directory|
      fake_player = File.join(directory, "ffplay")
      File.write(fake_player, "#!/bin/sh\nexit 0\n")
      File.chmod(0o755, fake_player)
      previous = ENV.fetch("PATH", nil)
      ENV["PATH"] = [".", directory].join(File::PATH_SEPARATOR)

      assert_equal fake_player, Dilla::SoundFx.send(:executable_path, "ffplay")
    ensure
      previous.nil? ? ENV.delete("PATH") : ENV["PATH"] = previous
    end
  end

  def test_events_have_distinct_sonic_signatures
    start = Dilla::SoundFx.render("start", sound_data: SOUND_DATA, engine_data: ENGINE_DATA, seed: 7)
    failure = Dilla::SoundFx.render("error", sound_data: SOUND_DATA, engine_data: ENGINE_DATA, seed: 7)
    refute_equal start, failure
  end

  def test_unknown_event_is_rejected
    assert_raises(ArgumentError) do
      Dilla::SoundFx.render("permission_prompt", sound_data: SOUND_DATA, engine_data: ENGINE_DATA, seed: 1)
    end
  end

  def test_cli_lists_events_without_rendering_a_full_track
    output, status = Open3.capture2e(RbConfig.ruby, SCRIPT, "sound-fx", "list")
    assert status.success?, output
    report = JSON.parse(output)
    assert_equal "ready", report.fetch("status")
    assert_equal EVENTS, report.fetch("events")
  end

  def test_hook_adapter_forwards_only_allowlisted_event_arguments
    hook = File.join(DIR, "sound_fx_hook.sh")
    Dir.mktmpdir("dilla-fx-hook-") do |directory|
      bin = File.join(directory, "bin")
      FileUtils.mkdir_p(bin)
      capture = File.join(directory, "argv.txt")
      fake_ruby = File.join(bin, "ruby")
      File.write(fake_ruby, "#!/bin/sh\nif [ \"${1:-}\" = \"-rjson\" ]; then\n  exec \"$DILLA_REAL_RUBY\" \"$@\"\nfi\nprintf \"%s\\n\" \"$@\" > \"$DILLA_CAPTURED_ARGS\"\n")
      File.chmod(0o755, fake_ruby)
      env = { "PATH" => [bin, "/usr/bin", "/bin"].join(File::PATH_SEPARATOR),
              "DILLA_CAPTURED_ARGS" => capture, "DILLA_REAL_RUBY" => RbConfig.ruby }

      _output, status = Open3.capture2e(env, "/bin/sh", hook, "complete")
      assert status.success?
      assert_equal [SCRIPT, "sound-fx", "complete", "--play"], File.readlines(capture, chomp: true)

      FileUtils.rm_f(capture)
      _output, status = Open3.capture2e(env, "/bin/sh", hook, "permission_prompt")
      assert status.success?
      refute File.exist?(capture), "non-contract event must not invoke the player/runtime"
    end
  end

  def test_hook_adapter_maps_claude_and_opencode_json_events
    hook = File.join(DIR, "sound_fx_hook.sh")
    Dir.mktmpdir("dilla-fx-hook-json-") do |directory|
      bin = File.join(directory, "bin")
      FileUtils.mkdir_p(bin)
      capture = File.join(directory, "argv.txt")
      fake_ruby = File.join(bin, "ruby")
      fake = [
        "#!/bin/sh",
        'if [ "${1:-}" = "-rjson" ]; then',
        '  exec "$DILLA_REAL_RUBY" "$@"',
        "fi",
        'printf "%s\\n" "$@" > "$DILLA_CAPTURED_ARGS"',
        ""
      ].join("\\n")
      File.write(fake_ruby, fake)
      File.chmod(0o755, fake_ruby)
      env = { "PATH" => [bin, "/usr/bin", "/bin"].join(File::PATH_SEPARATOR),
              "DILLA_CAPTURED_ARGS" => capture, "DILLA_REAL_RUBY" => RbConfig.ruby }

      claude_payload = JSON.generate("hook_event_name" => "SessionStart")
      _output, status = Open3.capture2e(env, "/bin/sh", hook, stdin_data: claude_payload)
      assert status.success?
      assert_equal [SCRIPT, "sound-fx", "start", "--play"], File.readlines(capture, chomp: true)

      FileUtils.rm_f(capture)
      opencode_payload = JSON.generate("event" => { "type" => "session.idle" })
      _output, status = Open3.capture2e(env, "/bin/sh", hook, stdin_data: opencode_payload)
      assert status.success?
      assert_equal [SCRIPT, "sound-fx", "complete", "--play"], File.readlines(capture, chomp: true)

      FileUtils.rm_f(capture)
      _output, status = Open3.capture2e(env, "/bin/sh", hook, stdin_data: "{not-json")
      assert status.success?
      refute File.exist?(capture), "invalid payload must not invoke Dilla or the player"
    end
  end
  def test_cli_writes_one_shot_wav_and_refuses_overwrite
    Dir.mktmpdir("dilla-fx-test-") do |directory|
      path = File.join(directory, "complete.wav")
      output, status = Open3.capture2e(RbConfig.ruby, SCRIPT, "sound-fx", "complete",
                                       "--out", path, "--seed", "112")
      assert status.success?, output
      assert File.file?(path)
      bytes = File.binread(path, 12)
      assert_equal "RIFF", bytes.byteslice(0, 4)
      assert_equal "WAVE", bytes.byteslice(8, 4)
      second, second_status = Open3.capture2e(RbConfig.ruby, SCRIPT, "sound-fx", "complete",
                                              "--out", path, "--seed", "112")
      refute second_status.success?
      assert_match(/overwrite existing take/i, second)
    end
  end
end
