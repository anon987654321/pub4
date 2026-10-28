# frozen_string_literal: true

require "minitest/autorun"
require "digest"
require_relative "../replicate/scene_compiler"
require_relative "../dilla/style_adapter"

class StudioAdaptersTest < Minitest::Test
  def test_scene_compiler_is_deterministic_and_hashes_prompt
    scene = { subject: "portrait", lighting: "softbox" }
    vocabulary = %w[portrait softbox]
    first = STUDIO::Replicate::SceneCompiler.compile(scene, vocabulary: vocabulary)
    second = STUDIO::Replicate::SceneCompiler.compile(scene, vocabulary: vocabulary)
    assert_equal :ready, first[:status]
    assert_equal first, second
    assert_equal Digest::SHA256.hexdigest(first[:prompt]), first[:prompt_sha256]
  end

  def test_scene_json_compiles_through_declared_prompt_vocabularies
    vocabularies = {
      stock: { "portra" => "Portra film response" },
      lighting: { "window" => "soft window light" }
    }
    compiler = ->(prompt, options) { [prompt, options[:stock], options[:lighting]].compact.join(", ") }
    result = STUDIO::Replicate::SceneCompiler.compile_fields(
      { "prompt" => "a candid portrait", "fields" => { "stock" => "Portra", "lighting" => "window" } },
      options: {}, vocabularies: vocabularies, compiler: compiler
    )

    assert_equal :ready, result[:status]
    assert_equal "a candid portrait, portra, window", result[:compiled_prompt]
    assert_equal 64, result[:compiled_prompt_sha256].length
  end

  def test_scene_json_rejects_unknown_fields_and_values_before_compilation
    called = false
    result = STUDIO::Replicate::SceneCompiler.compile_fields(
      { "prompt" => "portrait", "fields" => { "unknown" => "value" } },
      options: {}, vocabularies: { stock: { "portra" => "film" } },
      compiler: ->(*) { called = true; "should not run" }
    )

    assert_equal :rejected, result[:status]
    refute called
    assert_match(/unknown vocabulary field/, result[:warnings].join)
  end

  def test_scene_compiler_rejects_unknown_terms
    result = STUDIO::Replicate::SceneCompiler.compile({ subject: "dragon" }, vocabulary: ["portrait"])
    assert_equal :rejected, result[:status]
    assert_match(/unresolved vocabulary/, result[:warnings].join)
  end

  def test_abc_requires_engine_validator_and_headers
    abc = "X:1\nT:Test\nM:4/4\nL:1/8\nK:C\nCDEF|"
    assert_raises(ArgumentError) { Dilla::StyleAdapter.validate_abc!(abc) }
    result = Dilla::StyleAdapter.validate_abc!(abc, validator: ->(_score) { [] })
    assert_equal :ready, result[:status]
  end

  def test_mix_parameters_are_bounded
    assert_equal :ready, Dilla::StyleAdapter.validate_mix_parameters!({ "vocal" => { gain_db: 2.0, pan: 0.1 } })[:status]
    assert_raises(ArgumentError) { Dilla::StyleAdapter.validate_mix_parameters!({ "vocal" => { pan: 2.0 } }) }
  end
end
