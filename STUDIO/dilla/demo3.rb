#!/usr/bin/env ruby
# frozen_string_literal: true

# demo3.wav — Dilla pocket from the engine, not from an ffmpeg wash.
# Leads off. Documented progressions. Dry 8-bit snare and a 4/4 kick sit
# on top of the join so they are not crushed by the catalogue grit.
Dir.chdir(__dir__)
ENV["BPM"] = "92"
ENV["LEAD_DENSITY"] = "0"
ENV["KICK_GAIN"] = "1.35"
ENV["KICK_SAMPLE_GAIN"] = "1.2"
ENV["DRUM_BUS_VOL"] = "1.2"
ENV["DILLA_OVERWRITE"] = "1"
require_relative "dilla"

dest = File.join(ROOT, "demo3.wav")
names = %w[fall_in_love quartal_mediants get_dis_money detroit so_what two_moons]
scratch = File.join(ROOT, "scratch", "demo3")
FileUtils.mkdir_p(scratch)
seed = (ENV["RENDER_SEED"] || Time.now.to_i).to_i
worker = {
  "BPM" => "92",
  "LEAD_DENSITY" => "0",
  "KICK_GAIN" => "1.35",
  "KICK_SAMPLE_GAIN" => "1.2",
  "DRUM_BUS_VOL" => "1.2",
  "DILLA_SHOWCASE_SECONDS" => "16",
  "RENDER_MODE" => "dillatime",
  "DRUM_PRESET" => "dillatime"
}
parts = names.each_with_index.map do |name, i|
  path = File.join(scratch, format("%02d_%s.wav", i, name))
  env = worker.merge("DILLA_PIECE" => name, "RENDER_SEED" => (seed + i).to_s)
  ok = system(env, RbConfig.ruby, File.join(ROOT, "dilla.rb"), "piece", name, path)
  abort "demo3: #{name} failed" unless ok && File.file?(path)
  path
end
Bed.join_catalogue(parts, dest, 0.4)
Bed.grit_catalogue!(dest)

dur = Bed.wav_seconds(dest)
tmp = File.join(Dir.tmpdir, "demo3_#{Process.pid}")
FileUtils.mkdir_p(tmp)
kick = File.join(tmp, "kick.wav")
snare = File.join(tmp, "snare.wav")
out = File.join(tmp, "out.wav")

# 4/4 kick with a click. Mixed last so grit does not squash it.
system("ffmpeg", "-y", "-loglevel", "error", "-f", "lavfi", "-t", format("%.3f", dur),
       "-i", "aevalsrc='0.5*(random(0)-0.5)*exp(-90*mod(t,0.652))+0.95*sin(2*PI*(55+80*exp(-60*mod(t,0.652)))*t)*exp(-11*mod(t,0.652))':s=44100:d=#{dur}",
       "-af", "asoftclip=type=tanh:threshold=0.5,highpass=f=20,lowpass=f=220,volume=6dB,alimiter=limit=0.97",
       kick) or abort "demo3: kick failed"

# 8-bit phaser snare on 2 and 4, also last in the chain.
system("ffmpeg", "-y", "-loglevel", "error", "-f", "lavfi", "-t", format("%.3f", dur),
       "-i", "aevalsrc='0.7*(random(0)-0.5)*exp(-16*mod(t+0.326,0.652))*gt(mod(t,0.652),0.30)*lt(mod(t,0.652),0.42)':s=44100:d=#{dur}",
       "-af", "acrusher=bits=8:mode=log:mix=0.7,aphaser=in_gain=0.5:out_gain=0.8:delay=3:decay=0.4:speed=0.4,asoftclip=type=tanh:threshold=0.55,highpass=f=200,lowpass=f=4000,volume=3dB",
       snare) or abort "demo3: snare failed"

system("ffmpeg", "-y", "-loglevel", "error", "-i", dest, "-i", kick, "-i", snare,
       "-filter_complex",
       "[0:a][1:a][2:a]amix=inputs=3:weights=1 1.2 0.7:duration=first:normalize=0,highpass=f=30,lowpass=f=6000,alimiter=limit=0.94[out]",
       "-map", "[out]", "-c:a", "pcm_s16le", out) or abort "demo3: mix failed"
FileUtils.mv(out, dest)
FileUtils.rm_rf(tmp)
mp3 = demo_encode_mp3(dest)
warn "ok: #{dest}"
warn "ok: #{mp3}" if mp3
