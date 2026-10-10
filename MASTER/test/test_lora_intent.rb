# frozen_string_literal: true

require_relative "test_helper"
require "shellwords"
require "tmpdir"
require_relative "../lib/io/media_intent"

# "generate me a selfie" has to reach STUDIO/lora/lora.rb with the right argv,
# and a paid request has to stay a dry run until the sentence confirms it.
class LoraIntentTest < Minitest::Test
  Lora = Master::Io::LoraIntent

  # Runs a sentence with the script call stubbed; returns [result, calls].
  def run_text(text, root: Dir.pwd)
    calls = []
    fake = lambda do |root:, tool:, arg:, env: {}|
      calls << { root:, tool:, argv: Shellwords.split(arg) }
      Master::Result.ok("lora: planned")
    end
    result = Master::Io::ScriptDispatch.stub(:run, fake) { Lora.dispatch(text, root:) }
    [result, calls]
  end

  def test_the_phrases_that_are_lora_requests_and_the_ones_that_are_not
    {
      "generate me a selfie" => true,
      "can you make a lora of ragnhild" => true,
      "generate a video with the lora of me" => true,
      "lora status" => true,
      "lag en selfie av meg" => true,
      "tell me about selfies" => false,
      "make a video of a cat" => false,
      "generate a kick drum" => false,
    }.each do |text, expected|
      assert_equal expected, Lora.handles?(text), text
    end
  end

  def test_a_selfie_is_a_dry_run_for_the_default_person_until_confirmed
    result, calls = run_text("generate me a selfie")

    assert result.ok?
    argv = calls.first[:argv]
    assert_equal "lora", calls.first[:tool]
    assert_equal %w[--subject johann --generate-replicate --set selfies], argv.first(5).values_at(0, 1, 2, 3, 4)
    assert_includes argv, "--dry-run"
    assert_match(/nothing was spent/, result.value![:output])
    assert result.value![:dry_run]
  end

  def test_confirming_runs_it_for_real
    _, calls = run_text("generate me a selfie, confirm")

    refute_includes calls.first[:argv], "--dry-run"
  end

  def test_a_named_person_and_a_count_are_honoured_and_capped
    _, calls = run_text("make 3 selfies of ragnhild")
    argv = calls.first[:argv]

    assert_equal "ragnhild", argv[argv.index("--subject") + 1]
    assert_equal 3, argv[argv.index("--only") + 1].split(",").length

    _, capped = run_text("make 40 selfies of ragnhild")
    assert_equal 8, capped.first[:argv][capped.first[:argv].index("--only") + 1].split(",").length
  end

  def test_two_people_in_one_request_is_refused
    result, calls = run_text("make a selfie of johann and ragnhild")

    refute result.ok?
    assert_empty calls
  end

  def test_training_is_a_dry_run_then_async_once_confirmed
    _, dry = run_text("train a lora of me")
    _, paid = run_text("train a lora of me, go ahead")

    assert_equal %w[--subject johann --train-replicate --dry-run], dry.first[:argv]
    assert_equal %w[--subject johann --train-replicate --async], paid.first[:argv]
  end

  def test_status_asks_nothing_and_spends_nothing
    result, calls = run_text("lora status")

    assert_equal ["--status"], calls.first[:argv]
    refute result.value![:dry_run]
  end

  def test_a_video_needs_a_still_and_says_how_to_get_one
    Lora.stub(:latest_selfie, nil) do
      result, calls = run_text("generate a video with the lora of me")

      refute result.ok?
      assert_match(/generate me a selfie/, result.message.to_s)
      assert_empty calls
    end
  end

  def test_a_video_animates_the_named_still_with_the_spoken_motion
    Dir.mktmpdir do |dir|
      still = File.join(dir, "07.jpg")
      File.write(still, "x")
      _, calls = run_text("make a video of ragnhild from #{still} where she turns and smiles, final")
      argv = calls.first[:argv]

      assert_equal still, argv[argv.index("--image") + 1]
      assert_equal "she turns and smiles, final", argv[argv.index("--prompt") + 1]
      assert_equal "final", argv[argv.index("--preset") + 1]
      assert_includes argv, "--dry-run"
    end
  end

  def test_the_latest_selfie_is_the_default_still_and_the_draft_preset_the_default
    Lora.stub(:latest_selfie, "/tmp/graded.jpg") do
      _, calls = run_text("generate a video with the lora of me")
      argv = calls.first[:argv]

      assert_equal "/tmp/graded.jpg", argv[argv.index("--image") + 1]
      assert_equal "draft", argv[argv.index("--preset") + 1]
      assert_match(/\Ahe looks at the camera/, argv[argv.index("--prompt") + 1])
    end
  end

  def test_media_intent_hands_the_sentence_to_lora_first
    assert Master::Io::MediaIntent.handles?("generate me a selfie")
    _, calls = run_text_via_media("generate me a selfie")

    assert_equal "lora", calls.first[:tool]
  end

  def run_text_via_media(text)
    calls = []
    fake = lambda do |root:, tool:, arg:, env: {}|
      calls << { tool:, argv: Shellwords.split(arg) }
      Master::Result.ok("planned")
    end
    [Master::Io::ScriptDispatch.stub(:run, fake) { Master::Io::MediaIntent.dispatch(text, root: Dir.pwd) }, calls]
  end

  def test_the_data_file_names_only_subjects_that_have_a_wrapper
    cfg = Lora.config
    studio = File.expand_path("../../STUDIO/lora", __dir__)

    cfg.fetch("subjects").each_key { |name| assert File.file?(File.join(studio, name, "lora")), name }
    assert_includes cfg.fetch("subjects").keys, cfg.fetch("me")
  end
end
