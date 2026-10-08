# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require_relative "test_helper"

class TtsMlxTest < Minitest::Test
  def test_chatterbox_mlx_script_uses_expression_controls_and_english_language
    Dir.mktmpdir("master-tts-mlx") do |dir|
      out_path = File.join(dir, "reply.mp3")
      reference = File.join(dir, "reference.wav")
      File.write(reference, "reference")
      seen = nil
      status = Struct.new(:success?).new(true)

      Master::Voice::Engines.stub(:convert_to_mp3, ->(wav, output) {
        File.write(output, "mp3")
        true
      }) do
        Master::Io::Exec.stub(
          :capture3,
          lambda do |_python, _flag, script|
            seen = script
            wav = script[/sf\.write\((["'])(.+?)\1,/, 2]
            File.write(wav, "wav") if wav
            ["", "", status]
          end,
        ) do
          result = Master::Voice::Engines.send(
            :try_mlx_python_api,
            "python3",
            "mlx-community/chatterbox-fp16",
            "hello there",
            "default",
            1.0,
            out_path,
            emotion: { exaggeration: 0.72, cfg_weight: 0.33 },
            rate: "-4%",
            pitch: "-12Hz",
            reference_clip: reference,
            cfg: {
              "exaggeration" => 0.45,
              "cfg_weight" => 0.33,
              "temperature" => 0.76,
              "repetition_penalty" => 1.15,
              "min_p" => 0.04,
              "top_p" => 0.92,
            },
          )

          assert result
        end
      end

      assert_includes seen, '"exaggeration": 0.72'
      assert_includes seen, '"cfg_weight": 0.33'
      assert_includes seen, '"temperature": 0.76'
      assert_includes seen, '"repetition_penalty": 1.15'
      assert_includes seen, '"min_p": 0.04'
      assert_includes seen, '"top_p": 0.92'
      assert_includes seen, '"lang_code": "en"'
      assert_includes seen, reference.inspect
      assert_includes seen, '"ref_audio"'
      refute_includes seen, 'lang_code="a"'
    end
  end

  def test_chatterbox_mlx_is_sent_to_python_api_not_legacy_cli
    calls = []
    Master::Voice::Engines.stub(:mlx_python, "python3") do
      Master::Voice::Engines.stub(
        :try_mlx_python_api,
        ->(*args, **kwargs) { calls << [args, kwargs]; true },
      ) do
        Master::Voice::Engines.stub(
          :try_mlx_cli,
          ->(*_args) { raise "legacy CLI must not handle Chatterbox" },
        ) do
          assert Master::Voice::Engines.send(
            :synth_mlx,
            "hello",
            "/tmp/master-tts-test.mp3",
            {
              "mlx_model" => "mlx-community/chatterbox-fp16",
              "mlx_voice" => "default",
              "mlx_speed" => 1.0,
              "reference_clip" => "",
              "cfg_weight" => 0.42,
            },
            { exaggeration: 0.5 },
            rate: "-5%",
            pitch: "0Hz",
          )
        end
      end
    end

    assert_equal 1, calls.length
    assert_equal "mlx-community/chatterbox-fp16", calls.first[0][1]
    assert_equal "-5%", calls.first[1][:rate]
    assert_equal "0Hz", calls.first[1][:pitch]
  end
end
