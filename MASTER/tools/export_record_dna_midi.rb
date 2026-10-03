# frozen_string_literal: true

require_relative "../STUDIO/dilla/lib/groove"
require_relative "../lib/trace/dmesg"

profile = ARGV.shift
unless profile
  Master::Trace::Dmesg.status("dilla0", "usage, ruby #{File.basename(__FILE__)} <melody_am|los_angeles|fantastic_1|fantastic_2> [dest.mid]", io: $stderr)
  exit 64
end

dest = ARGV.shift || File.expand_path("../../STUDIO/dilla/project/#{profile}.mid", __dir__)
chords = {
  "melody_am" => %w[Dm7 Am7 Ebmaj7 Bb],
  "los_angeles" => %w[Dm9 G13 Cmaj9 Fmaj7],
  "fantastic_1" => %w[Fm9 Bbm9 Ebmaj9 Abmaj9],
  "fantastic_2" => %w[Cm9 Fm9 Bb13 Ebmaj7 Abmaj7 Dm7b5 G7alt Cm9],
}.fetch(profile) do
  Master::Trace::Dmesg.status("dilla0", "unknown record DNA profile, #{profile}", io: $stderr)
  exit 64
end

result = DillaRecordDna.write_midi(
  profile,
  chords:,
  bars: DillaRecordDna.profile(profile).fetch("phrase_bars", 8).to_i * 2,
  dest:,
  seed: Integer(ENV.fetch("DILLA_DNA_SEED", "4242"), 10),
  bpm: Integer(ENV.fetch("DILLA_DNA_BPM", "90"), 10),
)

Master::Trace::Dmesg.status("dilla0", "#{profile}, #{result[:bars]} bars, #{result[:notes]} notes, #{dest}")
