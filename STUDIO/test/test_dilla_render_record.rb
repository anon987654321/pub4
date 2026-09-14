# frozen_string_literal: true

require_relative "studio_helper"
require "json"
require "tmpdir"
require File.expand_path("../dilla/lib/ledger", __dir__)
require File.expand_path("../dilla/lib/listen", __dir__)

# What a render's record says about it beyond the seed: which toolchain made
# it, whether a stage gave up along the way, and what it loses in mono. Each is
# checked against a case whose answer is known before the instrument runs,
# because in this tree the instrument is wrong more often than the render.
class TestDillaRenderRecord < Minitest::Test
  def tone(dir, name, right)
    path = File.join(dir, "#{name}.wav")
    system("ffmpeg", "-v", "error", "-y", "-filter_complex",
           "sine=frequency=80:duration=1[a];sine=frequency=80:duration=1,#{right}[b];" \
           "[a][b]join=inputs=2:channel_layout=stereo[o]",
           "-map", "[o]", path, exception: true)
    path
  end

  def test_the_engine_identity_names_the_toolchain_that_rendered_it
    identity = DillaProvenance.engine_identity

    assert_match(/\A\d+\.\d+/, identity.fetch("ffmpeg"), "ffmpeg is installed here, so its version must be read")
    assert identity.key?("fluidsynth"), "fluidsynth is recorded even when it cannot be asked"
  end

  def test_a_warning_reaches_the_manifest_and_a_quiet_run_writes_no_key
    DillaProvenance.instance_variable_set(:@warning_count, 0)
    DillaProvenance.instance_variable_set(:@recorded_warnings, [])
    assert_nil DillaProvenance.warnings_record, "nothing warned, so nothing is flagged"

    DillaProvenance.tap_warnings!
    DillaProvenance.tap_warnings!
    capture_io { warn "sample_flip: crate empty, flip skipped" }
    capture_io { DillaDmesg.warn("speech tts segment failed") }

    record = DillaProvenance.warnings_record
    assert_equal 2, record.fetch("count"), "one Kernel#warn and one dmesg warn, and a second tap does not double them"
    assert_includes record.fetch("lines"), "sample_flip: crate empty, flip skipped"
    assert(record.fetch("lines").any? { |line| line.include?("speech tts segment failed") })
  ensure
    DillaProvenance.instance_variable_set(:@warning_count, 0)
    DillaProvenance.instance_variable_set(:@recorded_warnings, [])
  end

  def test_the_warning_list_is_capped_but_the_count_is_not
    DillaProvenance.instance_variable_set(:@warning_count, 0)
    DillaProvenance.instance_variable_set(:@recorded_warnings, [])
    (DillaProvenance::WARNING_LIMIT + 5).times { |i| DillaProvenance.record_warning("bar #{i}") }

    record = DillaProvenance.warnings_record
    assert_equal DillaProvenance::WARNING_LIMIT + 5, record.fetch("count")
    assert_equal DillaProvenance::WARNING_LIMIT, record.fetch("lines").size
  ensure
    DillaProvenance.instance_variable_set(:@warning_count, 0)
    DillaProvenance.instance_variable_set(:@recorded_warnings, [])
  end

  def test_mono_fold_reads_nothing_lost_for_mono_and_everything_for_cancelling_channels
    Dir.mktmpdir do |dir|
      mono = SpectralAudit.mono_fold(tone(dir, "mono", "anull"))
      inverted = SpectralAudit.mono_fold(tone(dir, "inverted", "volume=-1"))

      assert_in_delta 0.0, mono.fetch("mono_fold_loss_db"), 0.2, "identical channels lose nothing when summed"
      assert_operator mono.fetch("low_side_to_mid_db"), :<, -60, "a mono bass has no side energy"
      assert_operator inverted.fetch("mono_fold_loss_db"), :>, 60, "inverted channels cancel in mono"
      assert_operator inverted.fetch("low_side_to_mid_db"), :>, 60, "and all of that low end is side"
    end
  end
end
