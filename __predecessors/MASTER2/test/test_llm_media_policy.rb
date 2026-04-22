# frozen_string_literal: true

require_relative "test_helper"

class TestLlmMediaPolicy < Minitest::Test
  def setup
    setup_db

    @orig_available = MASTER::Replicate.method(:available?)
    @orig_generate = MASTER::Replicate.method(:generate)
    @orig_run = MASTER::Replicate.method(:run)
  end

  def teardown
    MASTER::Replicate.define_singleton_method(:available?, @orig_available)
    MASTER::Replicate.define_singleton_method(:generate, @orig_generate)
    MASTER::Replicate.define_singleton_method(:run, @orig_run)
    teardown_db
  end

  def test_paint_requires_replicate
    MASTER::Replicate.define_singleton_method(:available?) { false }

    result = MASTER::LLM.paint("hello")
    assert result.err?
    assert_match(/Replicate API token required/, result.error)
  end

  def test_paint_routes_to_replicate_generate
    MASTER::Replicate.define_singleton_method(:available?) { true }
    MASTER::Replicate.define_singleton_method(:generate) do |prompt:, model: nil, params: {}|
      MASTER::Result.ok(url: "https://example.com/image.png", prompt: prompt, model: model)
    end

    result = MASTER::LLM.paint("sunset")
    assert result.ok?
    assert_equal "https://example.com/image.png", result.value[:url]
    assert_equal "sunset", result.value[:prompt]
  end

  def test_transcribe_requires_replicate
    MASTER::Replicate.define_singleton_method(:available?) { false }

    result = MASTER::LLM.transcribe("sample.wav")
    assert result.err?
    assert_match(/Replicate API token required/, result.error)
  end

  def test_transcribe_routes_to_replicate_run
    MASTER::Replicate.define_singleton_method(:available?) { true }
    MASTER::Replicate.define_singleton_method(:run) do |model_id:, input:, params: {}|
      MASTER::Result.ok(text: "ok", model_id: model_id, input: input)
    end

    result = MASTER::LLM.transcribe("sample.wav")
    assert result.ok?
    assert_equal MASTER::Replicate::MODELS[:whisper], result.value[:model_id]
    assert_equal "sample.wav", result.value[:input][:audio]
  end
end
