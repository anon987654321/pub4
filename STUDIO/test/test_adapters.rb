# frozen_string_literal: true

require "minitest/autorun"
require "digest"
require "json"
require "tmpdir"
require "fileutils"
require "open3"
require "rbconfig"
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

  def test_score_check_uses_abc2midi_and_does_not_render
    Dir.mktmpdir do |dir|
      score = File.join(dir, "score.abc")
      File.write(score, "X:1\nT:Test\nM:4/4\nL:1/8\nK:C\nCDEF|\n")
      bin = File.join(dir, "bin")
      FileUtils.mkdir_p(bin)
      checker = File.join(bin, "abc2midi")
      File.write(checker, "#!/bin/sh\nexit 0\n")
      FileUtils.chmod(0o755, checker)
      env = { "PATH" => [bin, ENV.fetch("PATH", "")].join(File::PATH_SEPARATOR) }
      script = File.expand_path("../dilla/score_check.rb", __dir__)
      output, status = Open3.capture2e(env, RbConfig.ruby, script, "--abc", score)

      assert status.success?, output
      result = JSON.parse(output)
      assert_equal "ready", result["status"]
      assert_equal "abc2midi", result["validator"]
      assert_equal false, result["rendered"]
      assert_equal "blue_hour", result.dig("style_contract", "id")
    end
  end

  def test_score_check_reports_unavailable_parser_without_claiming_success
    Dir.mktmpdir do |dir|
      score = File.join(dir, "score.abc")
      File.write(score, "X:1\nT:Test\nM:4/4\nL:1/8\nK:C\nCDEF|\n")
      script = File.expand_path("../dilla/score_check.rb", __dir__)
      output, status = Open3.capture2e({ "PATH" => dir }, RbConfig.ruby, script, "--abc", score)

      assert_equal 3, status.exitstatus
      result = JSON.parse(output)
      assert_equal "unavailable", result["status"]
      assert_match(/not installed/, result["reason"])
    end
  end

  def test_abc_requires_engine_validator_and_headers
    abc = "X:1\nT:Test\nM:4/4\nL:1/8\nK:C\nCDEF|"
    assert_raises(ArgumentError) { Dilla::StyleAdapter.validate_abc!(abc) }
    result = Dilla::StyleAdapter.validate_abc!(abc, validator: ->(_score) { [] }, style_id: "blue_hour")
    assert_equal :ready, result[:status]
    assert_equal "blue_hour", result.dig(:style_contract, :id)
    assert_equal "1.0.0", result.dig(:style_contract, :version)
  end

  def test_mix_parameters_are_bounded
    assert_equal :ready, Dilla::StyleAdapter.validate_mix_parameters!({ "vocal" => { gain_db: 2.0, pan: 0.1 } })[:status]
    assert_raises(ArgumentError) { Dilla::StyleAdapter.validate_mix_parameters!({ "vocal" => { pan: 2.0 } }) }
    styled_mix = Dilla::StyleAdapter.validate_mix_parameters!(
      { "vocal" => { gain_db: 1.0 } }, style_id: "blue_hour"
    )
    assert_equal "blue_hour", styled_mix.dig(:style_contract, :id)
  end
end
