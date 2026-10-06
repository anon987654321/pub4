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
  DEFAULT_PATCH = "memorymoog_organ"

  class Score
    attr_reader :rng

    LOOKAHEAD_SECONDS = 1.0

    def initialize(events:, length:, rng:, patch:)
      @events = events
      @length = length
      @rng = rng
      @patch = LiveSynth::Patches.name!(patch)
      @knobs = LiveSynth::Knobs.new({}, response: LiveSynth::Demo::RESPONSE, rng:)
      @index = 0
    end

    def knobs = @knobs

    def describe = "Bach Toccata and Fugue BWV 565 MIDI, Dilla #{@patch}"

    def finished?(clock) = @index >= @events.length && clock >= @length

    def schedule(stage, clock)
      spec = LiveSynth::Patches.spec(@patch)
      while @index < @events.length && @events[@index][:at] < clock + LOOKAHEAD_SECONDS
        event = @events[@index]
        stage.note(event[:pitch], spec, event[:at], event[:held], event[:gain], :pad)
        @index += 1
      end
    end

    def command(command, clock)
      return unless command["knob"]

      LiveSynth::Say.turn!(@knobs, command, clock)
    end

    def overdub!(_left, _right, _clock, _rate) = nil

    def player_command(rate, dest)
      LiveSynth.through_ffmpeg(channels: 2,
                               filter: ["-af", "aecho=0.8:0.88:1100|1700:0.28|0.20,alimiter=limit=0.94"],
                               rate:, dest:) ||
        abort("live0: Bach leaves through ffmpeg -- install ffmpeg and sox")
    end
  end

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

  # Read Standard MIDI directly. No resampling, quantising or invented notes:
  # note-on/off pairs become the same pitch, duration and relative timing in
  # seconds, with the file's tempo map applied before Dilla renders them.
  FUGUE_START_MEASURES = 29
  FUGUE_MEASURES = 97
  BEATS_PER_MEASURE = 4

  def parse(path, section: :all)
    bytes = File.binread(path)
    raise ArgumentError, "not a Standard MIDI file" unless bytes.byteslice(0, 4) == "MThd"

    header_size = bytes.byteslice(4, 4).unpack1("N")
    raise ArgumentError, "invalid MIDI header" if header_size < 6

    format, track_count, division = bytes.byteslice(8, 6).unpack("n3")
    raise ArgumentError, "unsupported MIDI division" if division.zero? || (division & 0x8000).positive?

    cursor = 8 + header_size
    tracks = []
    tempo_events = []
    markers = []

    track_count.times do
      raise ArgumentError, "truncated MIDI track" unless bytes.byteslice(cursor, 4) == "MTrk"

      length = bytes.byteslice(cursor + 4, 4).unpack1("N")
      track = bytes.byteslice(cursor + 8, length)
      raise ArgumentError, "truncated MIDI track data" unless track&.bytesize == length

      parsed = parse_track(track)
      tracks << parsed
      tempo_events.concat(parsed[:tempos])
      markers.concat(parsed[:markers])
      cursor += 8 + length
    end

    tempos = [[0, 500_000], *tempo_events].sort_by(&:first)
    tempos = tempos.chunk_while { |a, b| a[0] == b[0] }.map(&:last)
    section_start_tick, section_end_tick = section_ticks(section, division, markers, tracks)
    section_start = tick_seconds(section_start_tick, division, tempos)
    section_end = section_end_tick && tick_seconds(section_end_tick, division, tempos)
    notes = tracks.flat_map { |track| track[:notes] }.filter_map do |note|
      next if note[:finish] <= section_start_tick
      next if section_end_tick && note[:start] >= section_end_tick

      start_tick = [note[:start], section_start_tick].max
      finish_tick = section_end_tick ? [note[:finish], section_end_tick].min : note[:finish]
      at = tick_seconds(start_tick, division, tempos) - section_start
      finish = tick_seconds(finish_tick, division, tempos) - section_start
      held = finish - at
      next if held <= 0.0

      {
        at:,
        held:,
        pitch: note[:pitch],
        gain: (note[:velocity].to_f / 127.0 * 0.56).clamp(0.08, 0.56),
      }
    end.sort_by { |note| [note[:at], note[:pitch]] }

    last_tick = section_end_tick || tracks.map { |track| track[:end_tick] }.max || 0
    length = tick_seconds(last_tick, division, tempos) - section_start
    [notes, length, format]
  end

  def parse_track(bytes)
    cursor = 0
    tick = 0
    running = nil
    active = Hash.new { |hash, key| hash[key] = [] }
    notes = []
    tempos = []
    markers = []

    while cursor < bytes.bytesize
      delta, cursor = read_vlq(bytes, cursor)
      tick += delta
      status = bytes.getbyte(cursor)

      if status && status >= 0x80
        cursor += 1
        running = status
      elsif running
        status = running
      else
        raise ArgumentError, "MIDI running status without a prior status"
      end

      case status & 0xF0
      when 0x80, 0x90
        raise ArgumentError, "truncated MIDI note event" if cursor + 2 > bytes.bytesize

        channel = status & 0x0F
        pitch = bytes.getbyte(cursor)
        velocity = bytes.getbyte(cursor + 1)
        cursor += 2
        key = [channel, pitch]

        if (status & 0xF0) == 0x90 && velocity.positive?
          active[key] << [tick, velocity]
        elsif active[key].any?
          start_tick, start_velocity = active[key].pop
          notes << { start: start_tick, finish: tick, pitch:, velocity: start_velocity }
        end
      when 0xA0, 0xB0, 0xE0
        cursor += 2
      when 0xC0, 0xD0
        cursor += 1
      when 0xF0
        case status
        when 0xF0, 0xF7
          length, cursor = read_vlq(bytes, cursor)
          cursor += length
          running = nil
        when 0xFF
          raise ArgumentError, "truncated MIDI meta event" if cursor >= bytes.bytesize

          type = bytes.getbyte(cursor)
          cursor += 1
          length, cursor = read_vlq(bytes, cursor)
          payload = bytes.byteslice(cursor, length)
          raise ArgumentError, "truncated MIDI meta payload" unless payload&.bytesize == length

          cursor += length
          tempos << [tick, (payload.getbyte(0) << 16) | (payload.getbyte(1) << 8) | payload.getbyte(2)] if type == 0x51 && length == 3
          markers << [tick, payload.to_s] if [0x01, 0x06, 0x07].include?(type) && payload && !payload.empty?
          running = nil
        else
          cursor += case status
                     when 0xF1, 0xF3 then 1
                     when 0xF2 then 2
                     else 0
                     end
          running = nil
        end
      end
    end

    active.each_value do |stack|
      stack.each do |start_tick, velocity|
        next if start_tick >= tick

        notes << { start: start_tick, finish: tick, pitch: nil, velocity: }
      end
    end

    notes.select! { |note| note[:pitch] }
    { notes:, tempos:, markers:, end_tick: tick }
  end

  def section_ticks(section, division, markers, tracks)
    return [0, tracks.map { |track| track[:end_tick] }.max || 0] unless section.to_sym == :fugue

    fugue = markers.find { |tick, text| text.match?(/\bfugue\b|\bfuga\b/i) }
    coda = markers.find { |tick, text| text.match?(/\brecitativo\b|\bcoda\b/i) && (!fugue || tick > fugue[0]) }
    start_tick = fugue&.first || (FUGUE_START_MEASURES * BEATS_PER_MEASURE * division)
    end_tick = coda&.first || ((FUGUE_START_MEASURES + FUGUE_MEASURES) * BEATS_PER_MEASURE * division)
    [start_tick, end_tick]
  end

  def read_vlq(bytes, cursor)
    value = 0
    loop do
      raise ArgumentError, "truncated MIDI variable-length value" if cursor >= bytes.bytesize

      byte = bytes.getbyte(cursor)
      cursor += 1
      value = (value << 7) | (byte & 0x7F)
      return [value, cursor] if (byte & 0x80).zero?
    end
  end

  def tick_seconds(tick, division, tempos)
    seconds = 0.0
    previous_tick = 0
    tempo = tempos.first[1]

    tempos.drop(1).each do |tempo_tick, next_tempo|
      break if tempo_tick > tick

      seconds += (tempo_tick - previous_tick) * tempo / (division * 1_000_000.0)
      previous_tick = tempo_tick
      tempo = next_tempo
    end

    seconds + ((tick - previous_tick) * tempo / (division * 1_000_000.0))
  end

  def play!
    path = source
    section = ENV.fetch("DILLA_BACH_SECTION", "fugue").to_sym
    abort "play: unsupported Bach section #{section.inspect}" unless %i[all fugue].include?(section)
    events, length, format = parse(path, section:)
    abort "play: Bach BWV 565 MIDI contains no playable notes" if events.empty?

    patch = ENV.fetch("DILLA_BACH_PATCH", DEFAULT_PATCH)
    title = section == :fugue ? "Bach Fugue BWV 565" : "Bach Toccata and Fugue BWV 565"
    puts "bach0: #{title} — original Mutopia MIDI section, format #{format}, #{events.length} notes"
    puts "bach0: Dilla synth #{patch}"
    LiveSynth.perform!(Score.new(events:, length:, rng: LiveSynth.rng!, patch:), seconds: length)
  rescue ArgumentError => e
    abort "play: invalid Bach MIDI — #{e.message}"
  end
end
