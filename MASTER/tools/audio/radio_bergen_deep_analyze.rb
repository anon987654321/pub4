#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "yaml"
require "open3"
require "fileutils"

ROOT = File.expand_path(__dir__)
MANIFEST = File.join(ROOT, "radio_bergen_tracks.yml")
OUT = File.join(ROOT, "..", "reports", "radio_bergen_track_dossiers.yml")

AUDIO_SEARCH_ROOTS = [
  File.expand_path("../../../../pub2", ROOT),
  File.expand_path("../../../../pub3/.index.html", ROOT),
  File.expand_path("../../../pub2/public", ROOT),
  File.expand_path("../../public", ROOT)
].freeze

# Curated production intelligence for reference tracks (no local audio / rights-safe).
REFERENCE_DOSSIERS = {
  "j_dilla_microphone_master" => {
    bpm: 90, key: "Fm / Ab", drum_preset: :dilla_slight, groove_dna: "donuts",
    drums: "MPC3000 swing ~57%; kick anchors 1 + late 3 (steps 0,6,10); snare 4/12 with early push; 8th-note hats with lazy upbeats; ghost snares on 2/10.",
    texture: "Dusty vinyl crackle, low-passed sample chop, warm sub; Donuts-era mono-stacked sample + live kit hybrid.",
    harmony: "Minor 7 → IV → bVII loop; sample-led melody with horn stab punctuation.",
    mix: "Soft clip + gentle compression; hats sit behind sample; kick/sub unified ~80–120 Hz.",
    dilla_engine: { track: "maj7_minor_cycle", performer: "yancey", kicks: "1", speak: "0" }
  },
  "j_dilla_in_space" => {
    bpm: 88, key: "Dm", drum_preset: :dilla_drunk, groove_dna: "donuts",
    drums: "Sparse pocket; kick drift on 0,3,6,13; snare 4/12 + ghost 7; hats staggered 16ths with wide humanize.",
    texture: "Spacey reverb tail on sample; filtered noise bed; minimal low end until hook.",
    harmony: "Two-chord hypnosis (Ebm7–Bbm7 feel); modal vamps with pitch-bent sample.",
    mix: "Wide stereo sample, dry center kick; high shelf rolled ~9 kHz.",
    dilla_engine: { track: "two_chord_hypnosis", performer: "yancey" }
  },
  "j_dilla_timeless" => {
    bpm: 86, key: "Fm9", drum_preset: :dilla_slight, groove_dna: "donuts",
    drums: "Canonical Dilla swing; kick 0,6,10; snare 4/12 early; 8th hats; occasional open hat on 14.",
    texture: "Timeless sample warmth, vinyl noise, bass shelf +9 dB; pad lowpass ~3.4 kHz.",
    harmony: "Fm9–Dbmaj9–Cm9 cycle; melody chop on 5th/9th tones.",
    mix: "Donuts lowpass warmth; integrated ~-19 LUFS feel; never harsh top.",
    dilla_engine: { track: "maj7_minor_cycle", performer: "yancey", sonic_key: "dilla_timeless" }
  },
  "afta_1_due_time" => {
    bpm: 91, key: "Bb", drum_preset: :dilla_slight, groove_dna: "donuts",
    drums: "Neo-soul slash grid; kick syncopated on 0,4,8; snare 4/12; clap layer; shaker on off-16ths.",
    texture: "Clean but swung; Rhodes-like midrange; round bass.",
    harmony: "Slash voicings Dm7/F–Fmaj9/A–Gm7/Bb; so-what voicing family.",
    mix: "Chris Dave pocket — drums slightly late, bass ahead.",
    dilla_engine: { track: "slash_neo_soul", performer: "chris_dave" }
  },
  "flying_lotus_massage_situation" => {
    bpm: 85, key: "Cm", drum_preset: :flylo_abstract, groove_dna: "wonky",
    drums: "Broken 16ths; kicks on 0,5,8,13; snares displaced 2,6,10,15; heavy ghost layer.",
    texture: "Glitch clicks, sidechain pump, stereo pan on hats; sub drops out for air.",
    harmony: "Quartal stacks; chromatic mediant drift.",
    mix: "Jazz haze sidechain; master lowpass ~3.6 kHz; vinyl 0.08.",
    dilla_engine: { track: "quartal_west_coast", performer: "glasper", groove_dna: "wonky" }
  },
  "madlib_eye" => {
    bpm: 96, key: "Dm", drum_preset: :sp303, groove_dna: "dust",
    drums: "SP-303 grit; straight-ish 8th hats; kick four-on-floor variant 0,4,8,12; snare 4/12.",
    texture: "Bitcrush 35% mix; vinyl 0.10; accordion/sample midrange dominant.",
    harmony: "Minor triad walk Dm–Gm–Am; simple loop hypnosis.",
    mix: "Dusty, mid-forward; limited highs; SP-1200 punch.",
    dilla_engine: { track: "minor_triad_walk", performer: "karriem_riggins" }
  },
  "slum_village_players" => {
    bpm: 93, key: "Dm", drum_preset: :mpc3000, groove_dna: "donuts",
    drums: "Players pocket: kick 0,6,10; snare 4/12; 8th hats; ghost 2/9; MPC swing 62%.",
    texture: "Neo-soul clean punch; bass sustain 0.92 bar; pad lowpass 3.3 kHz.",
    harmony: "Dm7–Eb7–Gm7–Am7; measured players progression.",
    mix: "Slum pocket — snare slightly early, hats late.",
    dilla_engine: { track: "neo_soul_pocket", performer: "questlove", sonic_key: "slum_players" }
  },
  "jay_electronica_exhibit_a" => {
    bpm: 86, key: "Bb / Dm", drum_preset: :madlib_dusty, groove_dna: "donuts",
    drums: "Slow drunk swing; kick 0,3,6,10,13; snare 4/7/12; sparse hats.",
    texture: "Cinematic strings sample + warm minor arc; vinyl 0.07.",
    harmony: "Dm7–Cm7–Fmaj9–Gm7 warm minor arc.",
    mix: "Wide sample, centered drums; long release tails.",
    dilla_engine: { track: "warm_minor_arc", performer: "yancey" }
  },
  "slum_village_la_la_instrumental" => {
    bpm: 94, key: "F minor", drum_preset: :dilla_drunk, groove_dna: "donuts",
    drums: "Donda-style drunk grid; kick 0,3,6,10,13; dense hat 16ths.",
    texture: "Dark minor loop; heavy bass shelf.",
    harmony: "Fm7–Abmaj7–Bbm7 loop.",
    dilla_engine: { track: "donda_minor", performer: "questlove" }
  },
  "slum_village_get_it_together" => {
    bpm: 92, key: "C minor", drum_preset: :mpc3000, groove_dna: "donuts",
    drums: "Classic boom-bap; kick four-on; snare 4/12; clap double.",
    texture: "Soul sample flip; filtered intro.",
    harmony: "Cm9–Fm7–Bbmaj7–Ebmaj9 neo-IV cycle.",
    dilla_engine: { track: "neo_iv_cycle", performer: "questlove" }
  },
  "slum_village_fantastic" => {
    bpm: 95, key: "Ab", drum_preset: :dilla_slight, groove_dna: "donuts",
    drums: "Upbeat swing; kick syncopated; open hat accents.",
    texture: "Bright soul sample; less vinyl than Donuts.",
    harmony: "Maj7 minor cycle variant.",
    dilla_engine: { track: "maj7_minor_cycle", performer: "questlove" }
  },
  "flying_lotus_me_yesterday_corded" => {
    bpm: 83, key: "D", drum_preset: :flylo_abstract, groove_dna: "wonky",
    drums: "Broken beat; irregular kick; snare clusters; glitch percussion.",
    texture: "Chopped vocal fragments; heavy stereo motion.",
    harmony: "Suspended ballad / chromatic drift.",
    dilla_engine: { track: "suspended_ballad", performer: "glasper" }
  },
  "flying_lotus_camel" => {
    bpm: 84, key: "C", drum_preset: :flylo_abstract, groove_dna: "wonky",
    drums: "Off-kilter 16ths; kick 0,5,8,13; snare 2,6,10,15; sidechain pump.",
    texture: "Quartal jazz haze; sidechain; vinyl 0.08; pan on arps.",
    harmony: "Cmaj9–Am9–Fmaj9–G6 quartal west coast.",
    mix: "FlyLo camel preset — master LP 3.6 kHz.",
    dilla_engine: { track: "quartal_west_coast", performer: "glasper", sonic_key: "flylo_camel" }
  },
  "flying_lotus_golden_diva" => {
    bpm: 82, key: "Eb", drum_preset: :flylo_abstract, groove_dna: "wonky",
    drums: "Slow loose pocket; minimal kick; brush-like hats.",
    texture: "Glasper quartal keys; long reverb.",
    harmony: "Ebmaj9–Cm9–Abmaj9–Bb6.",
    dilla_engine: { track: "glasper_quartal", performer: "glasper" }
  },
  "slum_village_worlds_full_of_sadness" => {
    bpm: 88, key: "G minor", drum_preset: :dilla_slight, groove_dna: "donuts",
    drums: "Melancholy swing; sparse kicks; rimshot ghosts.",
    texture: "Waterfall pad wash; minor soul loop.",
    harmony: "Gm9–Cm7–Fmaj9–Bbm7 watermelon turn.",
    dilla_engine: { track: "watermelon_turn", performer: "questlove" }
  },
  "a_mochi_takaaki_itoh_sarria_s_mind" => {
    bpm: 124, key: "D mixolydian", drum_preset: :mpc3000, groove_dna: "wonky",
    drums: "Techno-influenced 4/4 with swing overlay; driving hats.",
    texture: "Modal safe loop; cleaner digital top.",
    harmony: "Dmaj9–Cm9–Gmaj9–A7 modal safe.",
    dilla_engine: { track: "modal_safe", performer: "glasper", bpm: 124 }
  },
  "samiyam_rounded" => {
    bpm: 96, key: "Dm", drum_preset: :sp303, groove_dna: "donuts",
    drums: "Dry modern punch; kick 0,4,8,12; tight snare; minimal ghosts.",
    texture: "Rounded sub; low vinyl; modern dry punch texture.",
    harmony: "Dm9–Em7–Ebmaj7–Dm.",
    dilla_engine: { track: "minor_iv_loop", performer: "yancey", sonic_key: "samiyam_rounded" }
  },
  "chase_swayze_traffic" => {
    bpm: 88, key: "G", drum_preset: :mpc3000, groove_dna: "donuts",
    drums: "Minor turnaround grid; kick 0,6,10; snare 4/12; steady 8th hats.",
    texture: "Bergen night rain pad; vinyl 0.07; pad LP 3.3 kHz.",
    harmony: "Bm7–Bm7–Cmaj9–Em7.",
    dilla_engine: { track: "minor_turnaround", performer: "yancey" }
  },
  "chase_swayze_underrated" => {
    bpm: 90, key: "F minor", drum_preset: :dilla_slight, groove_dna: "donuts",
    drums: "Slightly drunk hat pattern; kick syncopation.",
    texture: "Lo-fi crunch; AKMD-family mastering.",
    harmony: "Minor IV loop.",
    dilla_engine: { track: "minor_iv_loop", performer: "yancey" }
  },
  "akmd_stailings" => {
    bpm: 87, key: "F# minor", drum_preset: :madlib_dusty, groove_dna: "donuts",
    drums: "Bergen lofi grid; kick 0,4,8,12 with humanize; swung hats; sparse clap.",
    texture: "AKMD mastering chain; night-rain pad; vinyl 0.08; LP 3.1 kHz.",
    harmony: "erykah_minor bill-evans voicing.",
    dilla_engine: { track: "erykah_minor", performer: "yancey", mix: "akmd_lofi_mastering" }
  },
  "akmd_mike_t_alt_kan_skje" => {
    bpm: 88, key: "F# minor", drum_preset: :madlib_dusty, groove_dna: "donuts",
    drums: "Same family as Stailings; slightly busier hat 16ths.",
    texture: "Lo-fi warmth; boosted 80/200 Hz per AKMD chain.",
    harmony: "erykah_minor cycle.",
    dilla_engine: { track: "erykah_minor", performer: "yancey" }
  },
  "akmd_mike_t_jan_hakim_diverse" => {
    bpm: 86, key: "C minor", drum_preset: :mpc3000, groove_dna: "donuts",
    drums: "Neo-IV pocket; kick 0,6,10; ghost snares.",
    texture: "Diverse arrangement — filter sweeps between sections.",
    harmony: "Cm9–Fm7–Bbmaj7–Ebmaj9 neo_iv_cycle.",
    dilla_engine: { track: "neo_iv_cycle", performer: "yancey" }
  },
  "angelo_reira_johann_sandviken_hotell_a" => {
    bpm: 85, key: "F# minor", drum_preset: :madlib_dusty, groove_dna: "donuts",
    drums: "Slow bergen swing; long kick sustain; rim ghosts.",
    texture: "Hotel-room ambience; heavy reverb on pad; AKMD LP.",
    harmony: "erykah_minor / keys_woman blend.",
    dilla_engine: { track: "erykah_minor", performer: "yancey" }
  },
  "angelo_reira_johann_sandviken_hotell_b" => {
    bpm: 84, key: "Eb", drum_preset: :madlib_dusty, groove_dna: "donuts",
    drums: "Companion to A; softer kick velocity; more pad-forward.",
    texture: "Warmer, less drum-forward than A.",
    harmony: "keys_woman Ebmaj9–Cm9–Fm7–Bb7.",
    dilla_engine: { track: "keys_woman", performer: "yancey" }
  },
  "haisam_johann_pb1" => {
    bpm: 89, key: "F# minor", drum_preset: :dilla_slight, groove_dna: "donuts",
    drums: "PB-series pocket; crisp snare; tight hats.",
    texture: "Cleaner top than Sandviken; still AKMD-mastered body.",
    harmony: "erykah_minor with iv_borrow_minor color.",
    dilla_engine: { track: "erykah_minor", performer: "yancey" }
  },
  "jan_hakim_johann_stailings_a" => {
    bpm: 87, key: "F# minor", drum_preset: :madlib_dusty, groove_dna: "donuts",
    drums: "Stailings variant; drunk hat stagger on 3,9,15.",
    texture: "Canonical Bergen stailings timbre — reference for local rotation.",
    harmony: "erykah_minor.",
    dilla_engine: { track: "erykah_minor", performer: "yancey" }
  },
  "mike_t_jr_rauingar" => {
    bpm: 90, key: "A minor", drum_preset: :dilla_slight, groove_dna: "donuts",
    drums: "Rauingar drive; kick syncopation 0,4,7,10; open hat on 14.",
    texture: "Slightly brighter hats; more energy in 4–8 kHz.",
    harmony: "iv_borrow_minor Am9–Dm9–Fmaj9–Em7.",
    dilla_engine: { track: "iv_borrow_minor", performer: "yancey" }
  },
  "flying_lotus_bts_radio_2006" => {
    bpm: 86, key: "varies", drum_preset: :flylo_abstract, groove_dna: "wonky",
    drums: "Live mix: long blends; percussion overdubs; tempo drift.",
    texture: "Radio collage; reverb throws; DJ-style filter sweeps.",
    harmony: "Multi-track medley — quartal + suspended ballads.",
    note: "Manifest start offset 1364s — deep in mix; treat as texture reference not grid template.",
    dilla_engine: { track: "quartal_west_coast", performer: "glasper" }
  }
}.freeze

LOCAL_NAME_ALIASES = {
  "/audio/akmd/akmd-stailings.mp3" => %w[akmd-stailings.mp3],
  "/audio/akmd/akmd_mike_t-alt_kan_skje.mp3" => %w[akmd_mike_t-alt_kan_skje.mp3 mike_t_and_johann-alt_kan_skje.mp3],
  "/audio/akmd/akmd_mike_t_jan_hakim-diverse.mp3" => %w[akmd_mike_t_jan_hakim-diverse.mp3],
  "/audio/akmd/angelo_reira_and_johann-sandviken_hotell_a.mp3" => %w[angelo_reira_and_johann-sandviken_hotell_a.mp3],
  "/audio/akmd/angelo_reira_and_johann-sandviken_hotell_b.mp3" => %w[angelo_reira_and_johann-sandviken_hotell_b.mp3],
  "/audio/akmd/chase_swayze-traffic.mp3" => %w[chase_swayze-traffic.mp3 chase_swayze-underated.mp3],
  "/audio/akmd/haisam_and_johann-pb1.mp3" => %w[haisam_and_johann-pb1.mp3],
  "/audio/akmd/jan_hakim_and_johann-stailings_a.mp3" => %w[jan_hakim_and_johann-stailings_a.mp3],
  "/audio/akmd/mike_t_jr-rauingar.mp3" => %w[mike_t_jr-rauingar.mp3 johann-rauingar.mp3]
}.freeze

module DeepAudio
  module_function

  def ffprobe(path)
    out, = Open3.capture2(
      "ffprobe", "-v", "error", "-show_entries", "format=duration,bit_rate:stream=sample_rate,channels",
      "-of", "json", path
    )
    JSON.parse(out)
  rescue StandardError
    {}
  end

  def band_rms(path, filter, window: 0.05, max_sec: 120)
    out, = Open3.capture2(
      "ffmpeg", "-hide_banner", "-loglevel", "error", "-t", max_sec.to_s, "-i", path,
      "-af", "#{filter},astats=metadata=1:reset=1:length=#{window},ametadata=print:key=lavfi.astats.Overall.RMS_level:file=-",
      "-f", "null", "-"
    )
    out.lines.filter_map do |line|
      next unless line.include?("RMS_level=")
      val = line.split("=").last.to_f
      val.finite? ? val : nil
    end.compact
  end

  def detect_onsets(rms_series, threshold_db: -18.0, min_gap: 3)
    onsets = []
    rms_series.each_with_index do |rms, i|
      next if rms < threshold_db
      prev = rms_series[i - 1] if i.positive?
      next if prev && prev >= threshold_db
      onsets << i if onsets.empty? || (i - onsets.last) >= min_gap
    end
    onsets
  end

  def estimate_bpm(onsets, window_sec: 0.05)
    return nil if onsets.length < 4
    intervals = onsets.each_cons(2).map { |a, b| (b - a) * window_sec }
    median = intervals.sort[intervals.length / 2]
    return nil if median.nil? || median <= 0
    raw = 60.0 / median
    # fold to common hip-hop range
    while raw < 70
      raw *= 2
    end
    while raw > 105
      raw /= 2
    end
    raw.round(1)
  end

  def analyze(path)
    return nil unless path && File.file?(path)

    meta = ffprobe(path)
    duration = meta.dig("format", "duration").to_f
    stream = Array(meta["streams"]).first || {}
    analyze_sec = [duration * 0.85, 120].min
    analyze_sec = duration if duration.positive? && duration < 120

    full = band_rms(path, "aformat=channel_layouts=stereo", window: 0.05, max_sec: analyze_sec)
    sub = band_rms(path, "lowpass=f=80", window: 0.05, max_sec: analyze_sec)
    kick = band_rms(path, "lowpass=f=200,highpass=f=60", window: 0.05, max_sec: analyze_sec)
    snare = band_rms(path, "lowpass=f=4000,highpass=f=800", window: 0.05, max_sec: analyze_sec)
    hats = band_rms(path, "lowpass=f=12000,highpass=f=4000", window: 0.05, max_sec: analyze_sec)

    avg = ->(arr) { arr.empty? ? nil : (arr.sum / arr.length).round(2) }
    max = ->(arr) { arr.empty? ? nil : arr.max.round(2) }

    kick_onsets = detect_onsets(kick, threshold_db: -14.0, min_gap: 4)
    bpm_kick = estimate_bpm(kick_onsets)
    snare_onsets = detect_onsets(snare, threshold_db: -16.0, min_gap: 4)
    bpm_snare = estimate_bpm(snare_onsets)

    crest = if full.any?
              peak = full.max
              rms = avg.call(full)
              rms ? (peak - rms).round(2) : nil
            end

    swing_hint = if kick_onsets.length >= 8
                   eighths = kick_onsets.each_cons(2).map { |a, b| b - a }
                   even = eighths.each_with_index.filter_map { |v, i| v if i.even? }
                   odd = eighths.each_with_index.filter_map { |v, i| v if i.odd? }
                   if even.any? && odd.any?
                     ratio = odd.sum.to_f / even.sum
                     ratio > 1.05 ? "laid_back" : ratio < 0.95 ? "pushed" : "straight"
                   end
                 end

    {
      measured: true,
      duration_seconds: duration.round(2),
      bit_rate: meta.dig("format", "bit_rate").to_i,
      sample_rate: stream["sample_rate"].to_i,
      channels: stream["channels"].to_i,
      bpm_estimate_kick: bpm_kick,
      bpm_estimate_snare: bpm_snare,
      bpm_estimate: [bpm_kick, bpm_snare].compact.then { |a| a.empty? ? nil : (a.sum / a.length).round(1) },
      loudness: {
        full_rms_db: avg.call(full), full_peak_db: max.call(full),
        sub_rms_db: avg.call(sub), kick_rms_db: avg.call(kick),
        snare_rms_db: avg.call(snare), hats_rms_db: avg.call(hats)
      },
      dynamics: { crest_factor_db: crest, swing_hint: swing_hint },
      drum_density: {
        kick_transients_per_min: kick_onsets.length * (60.0 / [analyze_sec, 1].max).round(1),
        snare_transients_per_min: snare_onsets.length * (60.0 / [analyze_sec, 1].max).round(1)
      },
      spectral_balance: spectral_balance(sub, kick, snare, hats),
      texture_hints: texture_hints(avg.call(sub), avg.call(kick), avg.call(hats), crest)
    }
  rescue StandardError => e
    { measured: false, error: e.message }
  end

  def spectral_balance(sub, kick, snare, hats)
    sub_a = sub.select { |v| v > -50 }
    kick_a = kick.select { |v| v > -50 }
    snare_a = snare.select { |v| v > -50 }
    hats_a = hats.select { |v| v > -50 }
    return {} if kick_a.empty?

    k = kick_a.sum / kick_a.length
    profile = {}
    profile[:sub_kick_ratio] = ratio(sub_a, k)
    profile[:snare_kick_ratio] = ratio(snare_a, k)
    profile[:hats_kick_ratio] = ratio(hats_a, k)
    profile[:brightness] = case profile[:hats_kick_ratio]
                           when nil then "unknown"
                           when ..-18 then "dark"
                           when -18..-12 then "warm"
                           else "bright"
                           end
    profile
  end

  def ratio(num_band, kick_avg)
    return nil if num_band.empty? || kick_avg.zero?
    n = num_band.sum / num_band.length
    (n - kick_avg).round(2)
  end

  def texture_hints(sub_rms, kick_rms, hats_rms, crest)
    hints = []
    hints << "heavy_sub" if sub_rms && sub_rms > -22
    hints << "lofi_rolled" if hats_rms && hats_rms < -28
    hints << "punchy_transients" if crest && crest > 12
    hints << "compressed_glue" if crest && crest < 8
    hints
  end
end

def slug(artist, title)
  "#{artist}-#{title}".downcase.gsub(/[^a-z0-9]+/, "_").gsub(/^_|_$/, "")
end

def resolve_audio(src)
  return nil if src.to_s.empty?
  names = LOCAL_NAME_ALIASES[src] || [File.basename(src)]
  AUDIO_SEARCH_ROOTS.each do |root|
    names.each do |name|
      path = File.join(root, name)
      return path if File.file?(path)
    end
  end
  nil
end

manifest = YAML.safe_load(File.read(MANIFEST), aliases: true)
rows = []
Array(manifest["local_mp3"]).each do |row|
  rows << { artist: row["artist"], title: row["title"], source: "local_mp3", src: row["src"], youtube_id: nil }
end
Array(manifest.dig("external_reference", "youtube")).each do |row|
  rows << { artist: row["artist"], title: row["title"], source: "youtube_reference",
            src: nil, youtube_id: row["id"], start: row["start"] }
end

dossiers = []
rows.each do |row|
  id = slug(row[:artist], row[:title])
  audio = resolve_audio(row[:src])
  measured = audio ? DeepAudio.analyze(audio) : nil
  reference = REFERENCE_DOSSIERS[id]

  entry = {
    id: id,
    artist: row[:artist],
    title: row[:title],
    source: row[:source],
    youtube_id: row[:youtube_id],
    audio_file: audio,
    analysis: measured,
    production_dossier: reference,
    engine_recommendation: reference&.dig(:dilla_engine) || {
      track: "erykah_minor", performer: "yancey", groove_dna: "donuts",
      kicks: "1", speak: "1", mix: "akmd_lofi_mastering"
    }
  }

  if measured && reference
    entry[:calibration_notes] = []
    if measured[:bpm_estimate] && reference[:bpm]
      delta = (measured[:bpm_estimate] - reference[:bpm]).abs
      entry[:calibration_notes] << "BPM delta #{delta.round(1)} (#{measured[:bpm_estimate]} measured vs #{reference[:bpm]} curated)" if delta > 4
    end
    entry[:calibration_notes] << "Swing: #{measured.dig(:dynamics, :swing_hint)}" if measured.dig(:dynamics, :swing_hint)
  end

  dossiers << entry
end

report = {
  meta: {
    generated_at: Time.now.utc.iso8601,
    manifest: MANIFEST,
    tracks: dossiers.length,
    measured_local: dossiers.count { |d| d[:analysis]&.dig(:measured) },
    reference_curated: dossiers.count { |d| d[:production_dossier] }
  },
  cross_track_learnings: {
    bergen_local: {
      drum_pattern: "madlib_dusty / mpc3000 hybrid; kicks 0,6,10; swung 8th hats; AKMD chain HPF 60 LPF 11.5k",
      texture: "bergen_night_rain pad wash; vinyl 0.07–0.08; bass shelf +9; master LP 2.7–3.1 kHz",
      harmony: "erykah_minor (F#m9–Bm7–Emaj7–C#m7); bill_evans voicing; swing 58%",
      bpm_cluster: "84–90"
    },
    dilla_canon: {
      drum_pattern: "MPC swing 54–62%; kick late-3 anchor; snare early on 4/12; ghost on 2/10",
      texture: "donuts_lowpass_warmth; vinyl 0.06; never harsh above 3.4 kHz on pads",
      harmony: "maj7_minor_cycle + minor_iv_loop family",
      bpm_cluster: "86–94"
    },
    flylo_canon: {
      drum_pattern: "flylo_abstract broken 16ths; kick 0,5,8,13; displaced snares",
      texture: "sidechain pump + jazz haze; quartal voicings; stereo pan hats",
      harmony: "quartal_west_coast / glasper_quartal",
      bpm_cluster: "82–88"
    },
    slum_canon: {
      drum_pattern: "neo_soul_pocket / mpc3000; players progression Dm7–Eb7–Gm7–Am7",
      texture: "cleaner punch than Donuts; bass sustain 0.92",
      bpm_cluster: "90–96"
    }
  },
  tracks: dossiers
}

FileUtils.mkdir_p(File.dirname(OUT))
File.write(OUT, report.transform_keys(&:to_s).to_yaml)
puts "wrote #{OUT}"
puts "measured #{report[:meta][:measured_local]}/#{manifest['local_mp3']&.length || 0} local tracks"
puts JSON.pretty_generate(report[:meta])