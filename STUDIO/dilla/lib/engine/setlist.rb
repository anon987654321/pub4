# frozen_string_literal: true
#
# Setlists: several takes and the environment they share.
#
# Part of the dilla engine, split out of dilla.rb. Defines methods and
# constants at top level exactly as it did there; dilla.rb requires the
# parts in the file's original order, because several constants are
# computed at load time from ones declared above them.

# --- Setlists ---
#
# A setlist is the recipe for a set of takes: which progression, which seed,
# and the render environment they were made under. It exists so a set can be
# rebuilt months later instead of being remembered.
#
# It is JSON with a .dilla extension, and it is readable by this engine rather
# than by a person alone -- a settings file nothing loads is a note that goes
# stale the first time a default moves under it, which is the failure mode this
# tree already has plenty of.
#
# Only the variables that change the rendered sound are captured. Recording the
# whole environment would sweep in DILLA_SH_TIMEOUT and RBENV_VERSION, which
# say nothing about the music and would fight the machine they are replayed on.
SETLIST_ENV_KEYS = %w[
  SU_MELODY SMOOTH_DRUMS MASTER_LUFS BPM FLUTES SCRAMBLE_SPEECH
  SINGERS_CHOP_PADS CHOIR_VOX PAD_GRANULAR NO_ARP MELODIC_LEAD
  LEAD_TIMBRE KICKS FORM RENDER_MODE STREAM_SOUL HARMONY_LEAD
].freeze

SETLIST_VERSION = 1

def setlist_engine_sha
  out, status = Open3.capture2("git", "-C", ROOT, "rev-parse", "--short", "HEAD")
  status.success? ? out.strip : nil
rescue StandardError
  nil
end

def save_setlist(path, takes: nil, bars: nil)
  takes ||= [{ "track" => ENV["TRACK"], "seed" => ENV["RENDER_SEED"] }]
  env = SETLIST_ENV_KEYS.each_with_object({}) do |k, h|
    v = ENV[k]
    h[k] = v unless v.nil? || v.empty?
  end
  doc = {
    # Named, because .dilla is now two formats. DillaProvenance writes one
    # beside every render as <output>.mp3.dilla: a single take, its seed, and
    # the command that rebuilds it. This is the other kind -- several takes and
    # the environment they share. The suffixes differ in practice, but a file
    # should say what it is rather than rely on how it happened to be named.
    "schema" => "setlist",
    "setlist_version" => SETLIST_VERSION,
    "engine_sha" => setlist_engine_sha,
    "bars" => (bars || ENV["BARS"] || 32).to_i,
    "env" => env,
    "takes" => takes,
  }
  File.write(path, JSON.pretty_generate(doc))
  dmesg("setlist saved: #{File.basename(path)} (#{takes.length} takes, #{env.length} settings)",
        unit: "set0", parent: "dilla0")
  path
end

def render_setlist(path, outdir = nil)
  abort("no such setlist: #{path}") unless File.file?(path)
  doc = JSON.parse(File.read(path))
  # Handed the other .dilla, say which one it is. Falling through to "no takes"
  # would blame the file for being empty when it is a different format
  # with its own command.
  if doc["schema"].to_s != "setlist" && doc.key?("render_seed") && doc.key?("command")
    abort("#{File.basename(path)} is a render manifest, not a setlist — use: ruby dilla.rb replay #{path}")
  end
  if doc["setlist_version"].to_i > SETLIST_VERSION
    abort("setlist v#{doc['setlist_version']} is newer than this engine understands (v#{SETLIST_VERSION})")
  end

  sha = doc["engine_sha"]
  here = setlist_engine_sha
  if sha && here && sha != here
    warn "setlist was written at #{sha}, replaying at #{here} — a default may have moved under it"
  end

  outdir ||= File.join(ROOT, "renders", "beats")
  FileUtils.mkdir_p(outdir)
  bars = (doc["bars"] || 32).to_i
  takes = Array(doc["takes"])
  abort("setlist has no takes") if takes.empty?

  written = takes.each_with_index.map do |take, i|
    name = take["name"] || format("take%d", i + 1)
    dest = File.join(outdir, "#{name}.mp3")
    env = (doc["env"] || {}).merge(
      "TRACK" => take["track"], "RENDER_SEED" => take["seed"]&.to_s
    ).reject { |_, v| v.nil? || v.to_s.empty? }
    dmesg("setlist take #{i + 1}/#{takes.length}: #{name} (#{take['track']}, seed #{take['seed']})",
          unit: "set0", parent: "dilla0")
    ok = system(env, Gem.ruby, ENGINE_FILE, "dilla", "--bars=#{bars}", dest)
    warn "setlist take #{name} failed" unless ok
    ok ? dest : nil
  end.compact

  dmesg("setlist done: #{written.length}/#{takes.length} takes -> #{outdir}", unit: "set0", parent: "dilla0")
  written
end
