# frozen_string_literal: true

require_relative "../test_helper"

class TestMotionCritique < Minitest::Test
  def test_offline_without_agent_or_vision
    verdict = Master::Judge::Council::MotionCritique.critique("/tmp/fake.mp4", "chase scene", agent: nil, vision: false)
    assert_equal :offline, verdict[:mode]
    assert verdict[:passed]
    assert_equal verdict[:score], verdict[:overall_score]
    assert_equal verdict[:weak_chunks], verdict[:flagged_chunks]
  end

  def test_synthesize_vision_report
    critique = Master::Judge::Council::MotionCritique.allocate
    critiques = {
      "editor" => { "persona" => "Editor", "score" => 8.0, "flagged_chunks" => [2], "notes" => "pacing dip" },
      "physicist" => { "persona" => "Physicist", "score" => 7.0, "flagged_chunks" => [2, 5], "notes" => "floaty" },
    }
    verdict = critique.send(:synthesize_vision_report, critiques, "/tmp/out.mp4")
    assert_in_delta 7.5, verdict[:score], 0.1
    assert_includes verdict[:weak_chunks], 2
    assert_equal :vision, verdict[:mode]
  end

  def test_parse_vision_json
    critique = Master::Judge::Council::MotionCritique.allocate
    parsed = critique.send(:parse_vision_json, '{"score": 8.5, "flagged_chunks": [3], "notes": "solid"}', "Cinematographer")
    assert_in_delta 8.5, parsed["score"], 0.01
    assert_equal [3], parsed["flagged_chunks"]
  end

  def test_synthesize_chunk_report_flags_failed_scenes
    critique = Master::Judge::Council::MotionCritique.allocate
    reviews = [
      { chunk: 0, scene: 1, score: 9.0, passed: true, notes: "good" },
      { chunk: 1, scene: 2, score: 5.5, passed: false, notes: "jitter" },
      { chunk: 2, scene: 3, score: 8.0, passed: true, notes: "ok" },
    ]
    verdict = critique.send(:synthesize_chunk_report, reviews, threshold: 7.5)
    assert_equal [2], verdict[:weak_chunks]
    assert_equal :per_chunk, verdict[:mode]
    assert_equal 3, verdict[:chunk_critiques].size
  end

  def test_critique_chunks_offline
    clips = ["/tmp/a.mp4", "/tmp/b.mp4"]
    verdict = Master::Judge::Council::MotionCritique.critique_chunks(
      clips: clips,
      original_prompt: "chase",
      vision: false,
      agent: nil
    )
    assert verdict[:passed]
    assert_equal :per_chunk, verdict[:mode]
    assert_empty verdict[:flagged_chunks]
  end
end