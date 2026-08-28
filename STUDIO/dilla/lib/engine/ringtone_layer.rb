# frozen_string_literal: true

# RINGTONE_LAYER=1 — the ringtone.tools devices, as one decision.
#
# lib/devices.rb carries four primitives ported from ringtone.tools: Copy Machine
# (one source played n times at once, the copies drifting in pitch and time), the
# Low Pass Gate (a note device whose decay darkens), wav_Map (an image read as a
# wavetable) and P_4L's voice stack (seven Plaits models under one macro knob).
# Each is measured and each is documented, and each was reachable only through its
# own off-by-default ENV knob -- COPY_MACHINE, LPG, WAV_MAP, VOICE_STACK. Four
# switches nobody flips together is four devices nobody hears together, which is
# how a whole shelf of built work stayed inaudible.
#
# This is the one switch. It sets the individual knobs as DEFAULTS, so an explicit
# COPY_MACHINE=0 or LPG_BLEND=0.4 still wins -- the layer is a starting position,
# not an override.
#
# wav_Map is deliberately NOT turned on here. It needs an image, and there is no
# sensible default picture; pass WAV_MAP=<path> and it joins the layer.
#
# The layer sits where the operator asked for it: audible as an effect, not as
# texture. Copy Machine runs the six copies its own default suggests, the LPG
# blends fully with a longer and droopier decay, and the voice stack doubles.
#
# It was conservative before -- three copies, 0.7 blend -- on the reasoning that
# Copy Machine replaces the bed and the bed is the loudest sampled thing in a
# render. That reasoning is sound and the numbers were still too quiet to hear.
#
# Wrapped in RingtoneLayer: dilla_resolve_config is the only external caller and
# it runs long after every part has loaded, so the qualified name costs nothing
# there. module_function keeps ringtone_layer_apply_env! callable bare from
# inside this module, which is what the load-time call at the bottom needs.
module RingtoneLayer
  module_function

  RINGTONE_LAYER_DEFAULTS = {
    "COPY_MACHINE" => "6",
    "COPY_MACHINE_FAMILY" => "harmonic",
    "COPY_MACHINE_REVERSE" => "0.35",
    "COPY_MACHINE_WIDTH" => "1.0",
    "COPY_MACHINE_DRIFT" => "320",
    "LPG" => "1",
    "LPG_BLEND" => "1.0",
    "LPG_DEPTH" => "1.0",
    "LPG_DECAY_MS" => "360",
    "LPG_DROOP" => "3.0",
    "VOICE_STACK" => "6",
  }.freeze

  def ringtone_layer_enabled? = ENV.fetch("RINGTONE_LAYER", "0") != "0"

  # Applied from dilla_resolve_config so every entry point gets it -- a render, the
  # demo, the stream -- rather than only the one that remembered to call it.
  def ringtone_layer_apply_env!
    return false unless ringtone_layer_enabled?
    return false if @ringtone_layer_applied

    @ringtone_layer_applied = true
    RINGTONE_LAYER_DEFAULTS.each { |k, v| ENV[k] ||= v }
    true
  end

  def ringtone_layer_describe
    return "ringtone layer: off" unless ringtone_layer_enabled?

    on = RINGTONE_LAYER_DEFAULTS.keys.map { |k| "#{k}=#{ENV[k]}" }
    on << "WAV_MAP=#{File.basename(ENV['WAV_MAP'].to_s)}" if File.file?(ENV["WAV_MAP"].to_s)
    "ringtone layer: #{on.join(' ')}"
  end

  # Applied at load rather than from dilla_resolve_config, because the render does
  # not go through that function -- wiring it there set the knobs in a process the
  # render never asked, and the devices ran on their own fallbacks while the log
  # said the layer was on. Load time is the only point every entry share.
  ringtone_layer_apply_env!
end
