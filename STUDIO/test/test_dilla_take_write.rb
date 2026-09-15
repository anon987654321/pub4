# frozen_string_literal: true

require_relative "dilla_helper"
require "fileutils"
require "tmpdir"

# A named take in OUTPUT_DIR is irreplaceable. The write site refuses rather
# than overwrite, unless DILLA_OVERWRITE=1. Scratch is PID-scoped and still
# overwrites; a retry of the same destination in one process is not a second take.
class TestTakeWrite < Minitest::Test
  def test_refuses_an_existing_named_take
    Dir.mktmpdir do |dir|
      path = File.join(dir, "loop.wav")
      File.write(path, "x")
      err = assert_raises(SystemExit) { send(:refuse_existing_take!, path) }
      assert_match(/refusing to overwrite existing take/, err.message)
      assert_includes err.message, path
      assert_match(/DILLA_OVERWRITE=1/, err.message)
      assert_equal "x", File.read(path)
    end
  end

  def test_overwrite_env_allows_the_write
    Dir.mktmpdir do |dir|
      path = File.join(dir, "loop.wav")
      File.write(path, "x")
      with_env("DILLA_OVERWRITE" => "1") { send(:refuse_existing_take!, path) }
    end
  end

  def test_scratch_still_overwrites
    path = File.join(SCRATCH_DIR, "dilla_take_write_#{Process.pid}.wav")
    FileUtils.mkdir_p(SCRATCH_DIR)
    File.write(path, "x")
    begin
      send(:refuse_existing_take!, path)
    ensure
      FileUtils.rm_f(path)
    end
  end

  # Two renders share SCRATCH_DIR. Each wipes its own pid-scoped files at the
  # top of a render and must leave the other's alone, or a concurrent demo and
  # stream delete each other's stems mid-mix.
  def test_scratch_cleanup_spares_another_process
    FileUtils.mkdir_p(SCRATCH_DIR)
    other_pid = Process.pid + 1_000_000
    mine = dilla_render_tmp("cleanup_probe")
    theirs = File.join(SCRATCH_DIR, "dilla_cleanup_probe.#{other_pid}.wav")
    File.write(mine, "x")
    File.write(theirs, "x")
    cleanup_render_scratch!

    refute File.exist?(mine), "this process's scratch file survived"
    assert File.exist?(theirs), "another process's scratch file was deleted"
  ensure
    FileUtils.rm_f([mine, theirs].compact)
  end

  def test_a_retry_of_the_same_take_is_not_a_second_take
    Dir.mktmpdir do |dir|
      path = File.join(dir, "loop.wav")
      send(:refuse_existing_take!, path)
      File.write(path, "x")
      send(:refuse_existing_take!, path)
    end
  end

  def test_stream_demo_is_a_rolling_capture
    Dir.mktmpdir do |dir|
      path = File.join(dir, "demo.wav")
      File.write(path, "x")
      with_env("DILLA_STREAMING" => "1", "STREAM_DEMO" => path) do
        send(:refuse_existing_take!, path)
      end
    end
  end
  # The stem rack is gitignored and its manifest is not, so a manifest naming
  # audio that is gone is the ordinary state of a fresh checkout. The check
  # names each missing stem and exits non-zero, and the liveset refuses before
  # ffmpeg is handed a path that is not there.
  def test_a_stem_rack_that_is_not_on_disk_is_refused
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "bass.wav"), "x")
      manifest = { "sets" => { "probe" => { "dir" => dir, "files" => %w[bass.wav drums.wav] } } }

      assert_equal [File.join(dir, "drums.wav")], send(:stems_missing, manifest)
      out, = capture_io { assert_raises(SystemExit) { send(:stems_check, manifest) } }
      assert_includes out, "MISSING  #{File.join(dir, "drums.wav")}"

      File.write(File.join(dir, "drums.wav"), "x")
      capture_io { send(:stems_check, manifest) }
    end
  end
  # The vocal catalogue is tracked and its audio is not, so the list says which
  # rows have no audio, and a directory kept for its record says why it is kept.
  def test_the_vocal_list_marks_missing_audio_and_says_why_a_record_is_kept
    Dir.mktmpdir do |dir|
      heard = File.join(dir, "heard.wav")
      File.write(heard, "x")
      %w[_mislabelled_untitled_flac j_dilla].each do |name|
        FileUtils.mkdir_p(File.join(dir, name))
        File.write(File.join(dir, name, "meta.json"), "{}")
      end
      catalog = { "vocals" => [
        { "slug" => "heard", "artist" => "A", "vocal_path" => heard, "phrases" => [{}] },
        { "slug" => "gone", "artist" => "B", "vocal_path" => File.join(dir, "gone.wav"), "phrases" => [] },
      ] }

      lines = send(:rap_vocal_list_lines, catalog, dir)

      refute_includes lines.find { |l| l.start_with?("heard") }, "audio missing"
      assert_includes lines.find { |l| l.start_with?("gone") }, "audio missing"
      assert_includes lines.find { |l| l.start_with?("_mislabelled_untitled_flac") }, "kept on purpose"
      assert_includes lines.find { |l| l.start_with?("j_dilla") }, "sidecar only"
    end
  end

  # A take a command keeps past its render is this process's own file, and the
  # shared name a later run reads is only ever replaced whole. harmony_loud.wav,
  # live_tmp.wav and jam_tmp.wav were written in place under one name, so two
  # processes sharing scratch wrote into the same file.
  def test_a_kept_take_is_this_process_file_and_is_published_whole
    take = send(:scratch_take, "probe_take.wav")
    assert_includes File.basename(take), ".#{Process.pid}.", "the take is not pid-scoped"
    refute_equal File.join(SCRATCH_DIR, "probe_take.wav"), take

    File.write(take, "new")
    shared = send(:publish_scratch!, take, "probe_take.wav")
    assert_equal File.join(SCRATCH_DIR, "probe_take.wav"), shared
    assert_equal "new", File.read(shared)
    refute File.exist?(take), "the take is still there beside the name it was published to"

    stems = "#{send(:scratch_take, 'probe_take.wav').delete_suffix('.wav')}_stems"
    FileUtils.mkdir_p(stems)
    File.write(File.join(stems, "drums.wav"), "fresh")
    FileUtils.mkdir_p(File.join(SCRATCH_DIR, "probe_take_stems"))
    File.write(File.join(SCRATCH_DIR, "probe_take_stems", "stale.wav"), "old")
    send(:publish_scratch!, stems, "probe_take_stems")
    assert_equal %w[drums.wav], Dir.children(File.join(SCRATCH_DIR, "probe_take_stems"))
  ensure
    FileUtils.rm_rf([File.join(SCRATCH_DIR, "probe_take.wav"), File.join(SCRATCH_DIR, "probe_take_stems")])
  end
end
