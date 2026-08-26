# frozen_string_literal: true
#
# The speaking voice over the stream.
#
# Part of the dilla engine, split out of dilla.rb. Defines methods and
# constants at top level exactly as it did there; dilla.rb requires the
# parts in the file's original order, because several constants are
# computed at load time from ones declared above them.

# --- Live playback ---

# Render a short preview and play it immediately via ffplay.
TTS_WORKER = File.expand_path("../../bin/tts-worker", ROOT)
# Funny-but-clear Edge voices — avoid heavy pitch/effects that hurt intelligibility.
SPEECH_VOICES = %w[en-US-AndrewNeural en-US-GuyNeural en-US-BrianMultilingualNeural].freeze
SPEECH_VOICE_DEFAULT = "en-US-AndrewNeural"
# MASTER's own TTS (MASTER/bin/tts-worker, Edge TTS one-shot mode) speaking
# over the beat — real speech, not a stub, mixed in quiet. Original pickup
# lines, not lyrics from any real song (those are copyrighted).
SPEECH_LINES = [
  "is your name Google? because you're everything I've been searching for",
  "are you made of copper and tellurium? because you're Cu-Te",
  "do you have a map? I just keep getting lost in your eyes",
  "if you were a vegetable, you'd be a cute-cumber",
  "are you a parking ticket? because you've got fine written all over you",
  "is there an airport nearby, or is that just my heart taking off",
  "do you believe in love at first sight, or should I walk by again",
  "are you a magician? because whenever I look at you, everyone else disappears",
  "I was going to say something really sweet about your smile, but you distracted me",
  "excuse me, I think you dropped something: my jaw",
  "are you French? because Eiffel for you",
  "if I could rearrange the alphabet, I'd put U and I together",
  "do you have a sunburn, or are you always this hot",
  "are you a campfire? because you're hot and I want s'more",
  "is it hot in here, or is it just you",
  "are you a time traveler? because I can totally see you in my future",
  "I'm not a photographer, but I can picture us together",
  "do you have a Band-Aid? because I just scraped my knee falling for you",
].freeze

# Comedic voice archetypes — text-level character, not a different TTS
# voice (Edge TTS gives no per-phrase SSML control, confirmed: only a
# single whole-utterance rate/pitch pair per call, no <break>/<emphasis>).
ARCHETYPE_LINES = [
  "aaand she reaches for the volume knob — CLASSIC move, folks",
  "you love to see it, absolute peak performance right there",
  "duuude, this whole track is, like, a whole vibe, for real",
  "it was a Tuesday. the coffee was cold. so was the mix",
  "if I may be so bold, your energy this evening is... quite something",
  "but wait — there's MORE. so much more",
  "ladies and gentlemen, what a play, what an absolute masterclass",
  "the pocket was tight that night. tighter than my budget",
  "one does not simply walk into a groove this deep",
].freeze

FILLER_SUBJECTS = %w[
  your smile your laugh that outfit this playlist your energy the room
  this beat your timing that look you your vibe this moment
].freeze
FILLER_VERBS = %w[
  is throwing off is stealing is rewriting is upgrading is complicating
  is improving is derailing is soundtracking is elevating is haunting
].freeze
FILLER_TOPICS = %w[
  my whole schedule my train of thought my entire plan my focus
  my Friday night my next three decisions my playlist my composure
].freeze

def filler_sentence(rng)
  "#{FILLER_SUBJECTS.sample(random: rng)} #{FILLER_VERBS.sample(random: rng)}, #{FILLER_TOPICS.sample(random: rng)}, yeah."
end

# Real text-level "impediment" character that stays intelligible: light
# stutter-repeat on ~1 in 6 words (never every word — that's where
# intelligibility actually breaks) and elongated vowels on emphasis words.
# Edge TTS renders repeated letters as real duration, so this reads as
# comic timing rather than garbage — confirmed, not assumed.
def quirkify(text, rng)
  words = text.split(" ")
  words.map do |w|
    clean = w.gsub(/[^a-zA-Z']/, "")
    next w if clean.length < 3
    if rng.rand < 0.16
      "#{clean[0]}-#{clean[0]}-#{w}"
    elsif rng.rand < 0.10
      w.sub(/([aeiouAEIOU])(?!.*[aeiouAEIOU])/) { $1 * 3 }
    else
      w
    end
  end.join(" ")
end

# Speech quirk lines — no faker gem; harmony/MIDI/WAV outsourced to :dilla gems when bundled —
# local word-bank generator instead, mixed with the curated lines, gives
# enough varied text to talk continuously rather than one clip per track.
def continuous_speech_text(duration, seed: nil)
  rng = seed ? Random.new(seed) : Random.new
  words_needed = (duration * 2.1).to_i
  sentences = []
  word_count = 0
  while word_count < words_needed
    s = case rng.rand
        when 0...0.28 then SPEECH_LINES.sample(random: rng)
        when 0.28...0.40 then ARCHETYPE_LINES.sample(random: rng)
        else filler_sentence(rng)
        end
    s = quirkify(s, rng) if rng.rand < speech_quirk_probability
    sentences << s
    word_count += s.split.length
  end
  scramble_words(sentences.join(" "), rng)
end

# Every word shuffled, so the delivery stays confident and the sense is gone.
#
# Shuffling inside each line kept too much of it -- short lines came back nearly
# intact and the pickup lines were still recognisable, which reads as a glitch
# rather than a joke. Pooling every word across the whole passage first is what
# makes it reliably nonsense: words land next to words from lines they never
# belonged to.
#
# Sentence lengths are preserved and the terminal punctuation is put back, so
# the TTS still phrases it as speech with commas and full stops in believable
# places. That contrast is the joke -- someone delivering total gibberish with
# the cadence of a man who means it. Scrambling the punctuation too would
# sound like a broken parser.
def scramble_words(text, rng)
  return text unless scramble_speech?

  lengths = text.split(/(?<=[.?!])\s+/).map { |s| s.split.length }
  bare = text.split.map { |w| w.gsub(/[.,!?]+\z/, "") }.reject(&:empty?)
  return text if bare.length < 4

  pool = bare.shuffle(random: rng)
  out = []
  lengths.each do |n|
    n = [n, pool.length].min
    break if n <= 0
    chunk = pool.shift(n)
    chunk[-1] = "#{chunk[-1]}#{rng.rand < 0.3 ? '?' : '.'}"
    out << chunk.join(" ")
  end
  out << pool.join(" ") if pool.any?
  out.join(" ")
end

def scramble_speech?
  ENV.fetch("SCRAMBLE_SPEECH", "1") != "0"
end

# Real structure, not a smooth gate: ~20-30s of talking, then ~20-30s of
# real silence, repeating — actual separately-synthesized segments placed
# at their own start times, not a tremolo faking it (tremolo's 0.1Hz floor
# can't reach a cycle this slow anyway).
SPEECH_TALK_SEC = 22.0
SPEECH_CYCLE_SEC = 62.0

def speech_quirk_probability
  ENV.fetch("SPEAK_QUIRK", "0.12").to_f.clamp(0.0, 1.0)
end

def speech_tts_voice
  v = ENV["SPEAK_VOICE"].to_s.strip
  return v if !v.empty? && SPEECH_VOICES.include?(v)
  SPEECH_VOICE_DEFAULT
end

def speech_tts_rate
  ENV.fetch("SPEAK_RATE", "-48%")
end

def speech_tts_pitch
  ENV.fetch("SPEAK_PITCH", "+8Hz")
end

def speech_talk_length
  base = if ENV["DILLA_STREAMING"] == "1"
           (ENV["SPEECH_TALK_STREAM"] || "14").to_f
         else
           SPEECH_TALK_SEC
         end
  base + (ENV["DILLA_STREAMING"] == "1" ? 0.0 : (rand - 0.5) * 6.0)
end

def speech_max_segments
  return unless ENV["DILLA_STREAMING"] == "1"
  [(ENV["SPEECH_MAX_SEGMENTS"] || "1").to_i, 1].max
end

def stream_track_banner(extra = nil)
  tag = ENV["TRACK"] || "?"
  lead_on = lead_arp_enabled? || harmony_lead_enabled?
  lead_tag = if lead_on
               ENV["LEAD_VOICE"] || @render_lead_patch&.dig(:id) || "on"
             else
               "0"
             end
  arp_tag = lead_on ? (ENV["LEAD_ARP_MODE"] || lead_arp_mode || pad_arp_mode) : "off"
  rap_tag = rap_vocal_stream_slug || "0"
  drum_tag = [
    ENV["DRUM_PRESET"] || "kit",
    ENV["POCKET_SET"],
    (ENV["FM_DRUMS"] == "0" ? "analog" : "fm"),
    (flylo_primary_drums? || ENV["FLYLO_DRUM_OVERLAY"] == "1" ? "flylo" : nil),
  ].compact.join("/")
  meta = "pad=#{ENV['PAD_VOICE']}/#{pad_arp_mode} lead=#{lead_tag}/#{arp_tag} " \
         "drums=#{drum_tag} rap=#{rap_tag} speak=#{ENV.fetch('SPEAK', '0')}"
  meta = "#{meta} #{extra}" if extra
  DillaDmesg.track!(tag, meta)
end

def speech_over_track_enabled?
  return false if ENV["SPEAK"] == "0"
  # Was auto-on whenever DILLA_STREAMING=1; now requires explicit SPEAK=1.
  ENV["SPEAK"] == "1"
end

def speak_over_track!(mp3_path, duration, _bpm = 90.0)
  return mp3_path unless File.executable?(TTS_WORKER) && tool_available?("ffmpeg")
  voice = speech_tts_voice
  rate = speech_tts_rate
  pitch = speech_tts_pitch
  segments = []
  # Never talk right at t=0 — that reads as a scripted "intro" every time a
  # track starts/loops. Let the track establish itself first.
  t = 10.0 + rand * 14.0
  idx = 0
  max_seg = speech_max_segments
  while t < duration
    break if max_seg && idx >= max_seg
    talk_len = speech_talk_length
    text = continuous_speech_text(talk_len, seed: idx + rand(100_000))
    seg_path = "#{mp3_path}.voice#{idx}.mp3"
    ok = false
    Open3.popen2(Gem.ruby, TTS_WORKER, voice, rate, pitch, seg_path) do |stdin, _stdout, wait|
      stdin.write(text)
      stdin.close
      ok = wait.value.success?
    end
    unless ok
      warn "speech: TTS segment #{idx} failed (#{voice})"
      break
    end
    segments << { path: seg_path, start: t } if File.exist?(seg_path) && File.size(seg_path) > 500
    t += SPEECH_CYCLE_SEC + (rand - 0.5) * 8.0
    idx += 1
  end
  return mp3_path if segments.empty?

  # Dry, intelligible speech over the beat — no echo/delay/chorus; timing only.
  vol = (ENV["SPEAK_VOL"] || "0.82").to_f
  inputs = []
  filter_parts = []
  labels = []
  segments.each_with_index do |seg, i|
    inputs += ["-i", seg[:path]]
    delay_ms = (seg[:start] * 1000).round
    filter_parts << "[#{i + 1}:a]aformat=channel_layouts=stereo," \
                     "highpass=f=90,lowpass=f=11000," \
                     "adelay=#{delay_ms}|#{delay_ms},volume=#{vol}[voice#{i}]"
    labels << "[voice#{i}]"
  end
  filter_parts << "#{labels.join}amix=inputs=#{labels.length}:duration=first:normalize=0[voicemix]"
  filter_parts << "[0:a][voicemix]amix=inputs=2:duration=first:normalize=0[out]"

  tmp = "#{mp3_path}.spoken.mp3"
  sh! "ffmpeg", "-y", "-i", mp3_path, *inputs,
      "-filter_complex", filter_parts.join(";"),
      "-map", "[out]", "-c:a", "libmp3lame", "-b:a", "320k", tmp
  FileUtils.mv(tmp, mp3_path)
  mp3_path
ensure
  segments&.each { |s| FileUtils.rm_f(s[:path]) } # scan: intentional — removes only the temp files this method rendered
end
