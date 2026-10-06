# frozen_string_literal: true

require "digest"
require "fileutils"
require "net/http"
require "tmpdir"
require "uri"


# Recover the operator's old Ableton beats without requiring Ableton Live itself.
# .als files are gzip-compressed XML; the Ableton reader already understands that
# document, so /play should use the real notes and their clip positions rather
# than inventing a progression from the set's name.
module AbletonPlay
  module_function

  DILLA_ROOT = File.expand_path("..", __dir__)
  CACHE_ROOT = File.join(Dir.home, ".cache", "master", "dilla")
  PPQ = 480
  DRUM_CHANNEL = 9

  def roots
    [
      ENV["ALS_ROOT"],
      File.join(Dir.home, "Downloads")
    ].compact.map { |path| File.expand_path(path) }.uniq.select { |path| File.directory?(path) }
  end

  def sets
    roots.flat_map do |root|
      Dir.glob(File.join(root, "**", "*.als")).reject { |path| path.match?(%r{/(?:Backup|Backups)/}i) }
    end.uniq.sort
  end

  def normalize(value)
    value.to_s.downcase
        .delete_suffix(".als")
        .gsub(/[^a-z0-9]+/, "_")
        .gsub(/\A_+|_+\z/, "")
  end

  def set_slug(path)
    folder = File.basename(File.dirname(path))
    raw = folder.match?(/ Project\z/i) ? folder.sub(/ Project\z/i, "") : File.basename(path, ".als")
    key = normalize(raw)
    key.empty? ? "ableton_set" : key
  end

  def candidates
    sets.map do |path|
      {
        path:,
        slug: set_slug(path),
        file: normalize(File.basename(path))
      }
    end
  end

  def locate(query)
    key = normalize(query)
    rows = candidates
    return nil if key.empty?

    exact = rows.select { |row| row[:slug] == key || row[:file] == key }
    return exact.first if exact.one?

    matched = rows.select do |row|
      parts = key.split("_")
      hay = "#{row[:slug]}_#{row[:file]}"
      parts.all? { |part| hay.include?(part) }
    end
    return matched.first if matched.one?

    nil
  end

  def play!(query)
    row = locate(query)
    unless row
      names = candidates.map { |candidate| candidate[:slug] }.uniq.first(24)
      detail = names.empty? ? "no .als files found under #{roots.join(", ")}" : "available: #{names.join(", ")}"
      abort "play: no Ableton set matching #{query.inspect}; #{detail}"
    end

    set = Ableton.set(row[:path])
    note_count = set.tracks.sum { |track| track.clips.sum { |clip| clip.notes.size } }
    abort "play: #{row[:slug]} contains no MIDI notes" if note_count.zero?

    digest = Digest::SHA256.hexdigest(File.expand_path(row[:path]))[0, 8]
    destination = File.join(CACHE_ROOT, "ableton", "#{row[:slug]}-#{digest}.mid")
    FileUtils.mkdir_p(File.dirname(destination))
    File.binwrite(destination, midi_file(set))

    puts "als0: #{row[:slug]} #{set.tempo.round(2)} bpm, #{note_count} notes"
    puts "als0: recovered #{row[:path]} -> #{destination}"
    puts "als0: playing the recovered MIDI, not an approximation"

    MIDIPlayback.play!(destination)
  end

  def midi_file(set)
    events = []
    set.tracks.each do |track|
      channel = Ableton.drums?(track) ? DRUM_CHANNEL : 0
      track.clips.each do |clip|
        clip.notes.each do |note|
          beat = clip.start.to_f + note.time.to_f
          duration = [note.duration.to_f, 0.05].max
          on = (beat * PPQ).round
          off = (beat + duration) * PPQ
          off = on + 1 if off <= on

          pitch = note.pitch.to_i.clamp(0, 127)
          velocity = note.velocity.to_f.round.clamp(1, 127)
          events << [on, 0x90 | channel, pitch, velocity]
          events << [off.round, 0x80 | channel, pitch, 0]
        end
      end
    end

    events.sort_by! { |tick, status, pitch, _velocity| [tick, status, pitch] }
    tempo = set.tempo.to_f
    tempo = 120.0 unless tempo.between?(20.0, 300.0)
    usec = (60_000_000 / tempo).round

    body = "\x00\xFF\x51\x03".b + [usec].pack("N")[1, 3]
    last = 0
    events.each do |tick, status, pitch, velocity|
      tick = [tick, last].max
      body << vlq(tick - last) << [status, pitch, velocity].pack("C3")
      last = tick
    end
    body << vlq(0) << "\xFF\x2F\x00".b

    "MThd".b + [6].pack("N") + [0, 1, PPQ].pack("n3") +
      "MTrk".b + [body.bytesize].pack("N") + body
  end

  def vlq(value)
    bytes = [value & 0x7f]
    value >>= 7
    while value.positive?
      bytes.unshift((value & 0x7f) | 0x80)
      value >>= 7
    end
    bytes.pack("C*").b
  end
end

require "digest"

module MIDIPlayback
  module_function

  def soundfont
    candidates = []
    candidates << LIVESET_SF if defined?(LIVESET_SF)
    candidates.concat(Dir.glob("/opt/homebrew/Cellar/fluid-synth/*/share/fluid-synth/sf2/*.sf2"))
    candidates.concat(Dir.glob("/opt/homebrew/share/sounds/sf2/*.sf2"))
    candidates.concat(Dir.glob("/usr/local/share/sounds/sf2/*.sf2"))
    candidates.find { |path| File.file?(path) && File.size?(path) }
  end

  def player
    defined?(Livesets) ? Livesets.tool("fluidsynth") : "fluidsynth"
  end

  def play!(midi)
    abort "play: missing MIDI #{midi}" unless File.file?(midi) && File.size?(midi).positive?

    sf = soundfont
    abort "play: no FluidSynth soundfont found" unless sf

    dir = Dir.mktmpdir("master-midi-")
    wav = File.join(dir, "render.wav")
    ok = system(player, "-ni", sf, midi, "-F", wav, "-r", "44100", "-g", "0.75")
    abort "play: fluidsynth failed for #{midi}" unless ok && File.file?(wav) && File.size?(wav).positive?

    system("afplay", wav)
  ensure
    FileUtils.remove_entry(dir) if dir && File.directory?(dir)
  end
end

module BachMidi
  module_function

  URL = URI("https://www.mutopiaproject.org/ftp/BachJS/BWV565/ToccataFugue/ToccataFugue.mid")
  CACHE = File.join(Dir.home, ".cache", "master", "dilla", "bach_bwv565.mid")

  def source
    return CACHE if File.file?(CACHE) && File.size?(CACHE).positive?

    FileUtils.mkdir_p(File.dirname(CACHE))
    body = fetch(URL)
    tmp = "#{CACHE}.#{Process.pid}.tmp"
    File.binwrite(tmp, body)
    File.rename(tmp, CACHE)
    CACHE
  rescue StandardError => e
    FileUtils.rm_f(tmp) if defined?(tmp) && tmp
    abort "play: could not fetch Bach BWV 565 MIDI — #{e.message}"
  end

  def fetch(uri, redirects: 0)
    abort "play: Bach MIDI redirect loop" if redirects > 5

    response = Net::HTTP.get_response(uri)
    case response
    when Net::HTTPSuccess
      response.body
    when Net::HTTPRedirection
      location = URI.join(uri.to_s, response["location"])
      fetch(location, redirects: redirects + 1)
    else
      abort "HTTP #{response.code}"
    end
  end

  def play!
    path = source
    puts "bach0: Bach Toccata and Fugue BWV 565 — original MIDI"
    MIDIPlayback.play!(path)
  end
end
