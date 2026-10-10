# frozen_string_literal: true

require "yaml"

# Turns "this still, this prompt, about this long" into the input one video
# model takes. The models disagree on the name of the first-frame input, on
# whether length is seconds or frames, and on which lengths exist at all, so the
# differences live in video_models.yml and this module only applies them.
module Video
  PRESETS_PATH = File.join(__dir__, "video_models.yml")

  module_function

  def presets = YAML.safe_load_file(PRESETS_PATH)

  def preset(name)
    presets.fetch(name) { raise ArgumentError, "unknown preset #{name.inspect}; have #{presets.keys.join(', ')}" }
  end

  def model_id(spec) = "#{spec.fetch('model')}:#{spec.fetch('version')}"

  # The nearest length the model offers, so asking for 7 seconds of a 6-or-8
  # model gives 6 or 8 rather than a refused request.
  def seconds_input(spec, seconds)
    return {} unless seconds

    rule = spec.fetch("seconds")
    if rule["frames"]
      frames = rule["frames"]
      count = (seconds * frames.fetch("fps")).round.clamp(frames.fetch("min"), frames.fetch("max"))
      { frames.fetch("key") => count, frames.fetch("fps_key") => frames.fetch("fps") }
    else
      { rule.fetch("key") => rule.fetch("allowed").min_by { |allowed| (allowed - seconds).abs } }
    end
  end

  def build_input(spec, prompt:, image_url:, seconds: nil, seed: nil, audio: nil)
    input = spec.fetch("input").transform_keys(&:to_s)
    input[spec.fetch("image_key")] = image_url
    input["prompt"] = prompt
    input.merge!(seconds_input(spec, seconds))
    input["seed"] = seed if seed && spec.fetch("seed", true)
    unless audio.nil?
      key = spec["audio_key"] or raise ArgumentError, "#{spec['model']} has no audio switch"
      input[key] = audio
    end
    input
  end
end
