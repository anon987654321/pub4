# frozen_string_literal: true

require "minitest/autorun"
require_relative "../dilla/lib/slskd_crate"

class TestSlskdCrate < Minitest::Test
  def test_audio_results_filters_non_audio
    state = {
      "responses" => [
        {
          "username" => "peer",
          "hasFreeUploadSlot" => true,
          "queueLength" => 2,
          "files" => [
            { "filename" => "break.flac", "size" => 10_000 },
            { "filename" => "cover.jpg", "size" => 20_000 },
          ],
        },
      ],
    }

    results = SlskdCrate.audio_results(state)
    assert_equal 1, results.length
    assert_equal "break.flac", results.first["filename"]
  end

  def test_rank_prefers_lossless_and_available_peers
    results = [
      { "filename" => "a.mp3", "size" => 20_000, "free_upload_slot" => true, "queue_length" => 0 },
      { "filename" => "b.flac", "size" => 10_000, "free_upload_slot" => false, "queue_length" => 20 },
      { "filename" => "c.wav", "size" => 10_000, "free_upload_slot" => true, "queue_length" => 1 },
    ]

    assert_equal "b.flac", SlskdCrate.rank(results).first["filename"]
  end

  def test_unknown_rights_are_blocked_without_explicit_opt_in
    skip if SlskdCrate::ALLOW_UNKNOWN
    error = assert_raises(RuntimeError) { SlskdCrate.require_release_rights! }
    assert_includes error.message, "SLSKD_ALLOW_UNKNOWN"
  end
end
