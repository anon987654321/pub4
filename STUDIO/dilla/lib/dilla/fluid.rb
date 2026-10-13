# frozen_string_literal: true

# ----------------------------------------------------------------- soundfont
# Strings, choir and warm pads that Ruby does not synthesise are played by the fluidsynth binary
# from a soundfont: the notes of a part are written as a Standard MIDI File, fluidsynth renders
# it with its own reverb and chorus off (the chorus is a modulation), and the wav is read back to
# be mixed in before the effects. Where the binary or the soundfont is missing the voice says so
# and the voice named as its fallback plays instead, and the rotation leaves it out.
module Fluid
  BINARIES = ['/opt/homebrew/bin/fluidsynth', '/usr/local/bin/fluidsynth', '/usr/bin/fluidsynth'].freeze
  FONT_GLOB = 'Downloads/pub3-main*/multimedia/dilla/tools/instruments/soundfonts'
  CACHE_DIR = '.cache/dilla-soundfonts'
  DEFAULT_FONTS = %w[FluidR3_GM.sf2 GeneralUser-GS.sf2].freeze # the first is the one the folder was meant to hold
  GAIN = 0.6
  TIMEOUT = 180

  def self.binary
    ENV.fetch('DILLA_FLUIDSYNTH', nil)&.then { |path| return path if File.executable?(path) }
    BINARIES.find { |path| File.executable?(path) } ||
      ENV.fetch('PATH', '').split(File::PATH_SEPARATOR).map { |dir| File.join(dir, 'fluidsynth') }.find { |path| File.executable?(path) }
  end

  # A soundfont is a RIFF file that says how long it is; a download cut short says so too, and
  # fluidsynth only fails on it at render time.
  def self.whole?(path)
    return false unless File.file?(path)

    head = File.binread(path, 12).to_s
    head.byteslice(8, 4) == 'sfbk' && head.byteslice(4, 4).unpack1('V') + 8 == File.size(path)
  end

  # DILLA_SOUNDFONT names one file for the default voices; otherwise the first whole file of the
  # names, looked for in the soundfont folder of the download, then in the cache folder.
  def self.soundfont(names = DEFAULT_FONTS)
    names = Array(names)
    given = ENV.fetch('DILLA_SOUNDFONT', nil)
    return (whole?(given) ? given : nil) if given && names == DEFAULT_FONTS

    folders = Dir.glob(File.join(Dir.home, FONT_GLOB)).sort + [File.join(Dir.home, CACHE_DIR)]
    folders.product(names).map { |folder, name| File.join(folder, name) }.find { |path| whole?(path) }
  end

  def self.available?(spec = {}) = !binary.nil? && !soundfont(spec.fetch('soundfont', DEFAULT_FONTS)).nil?

  # Why a fluid voice cannot play, in words, or nil when it can.
  def self.missing(spec = {})
    return 'the fluidsynth binary was not found' unless binary

    names = Array(spec.fetch('soundfont', DEFAULT_FONTS))
    soundfont(names) ? nil : "no whole soundfont among #{names.join(', ')} (DILLA_SOUNDFONT names one)"
  end

  # The argv for one render: no shell sees it.
  def self.command(wav, font, midi) = [binary, '-ni', '-F', wav, '-r', SAMPLE_RATE.to_s, '-g', GAIN.to_s, '-R', '0', '-C', '0', font, midi]

  # Mono samples of the plucks played by the voice's program, from time zero, with the
  # soundfont's releases after the last note. A chord pluck sounds every note it holds.
  def self.render(plucks, spec)
    font = soundfont(spec.fetch('soundfont', DEFAULT_FONTS)) or raise ArgumentError, missing(spec)
    notes = plucks.flat_map do |p|
      start = [p.base + p.off.clamp(-MAX_OFFSET, MAX_OFFSET), 0.0].max
      Array(p.midi).map { |midi| [start, p.dur, midi, (30 + (97 * p.gain.clamp(0.0, 1.0))).round] }
    end
    return [] if notes.empty?

    Dir.mktmpdir('dilla-fluid') do |dir|
      midi = File.join(dir, 'part.mid')
      wav = File.join(dir, 'part.wav')
      MIDI.write_notes(midi, notes, program: spec.fetch('program'), bank: spec.fetch('bank', 0))
      run(command(wav, font, midi), dir)
      read(wav)
    end
  end

  def self.run(argv, dir)
    log = File.join(dir, 'fluidsynth.log')
    pid = Process.spawn(*argv, in: File::NULL, out: log, err: [:child, :out])
    status = Timeout.timeout(TIMEOUT) { Process.wait2(pid).last }
    raise "fluidsynth failed: #{File.read(log).lines.last(3).join.strip}" unless status.success?
  rescue Timeout::Error
    Process.kill('KILL', pid)
    Process.wait(pid)
    raise 'fluidsynth timed out'
  end

  # A 16-bit PCM wav of one or two channels, mixed down to mono.
  def self.read(path)
    bytes = File.binread(path)
    raise 'fluidsynth wrote no wav' unless bytes.byteslice(0, 4) == 'RIFF' && bytes.byteslice(8, 4) == 'WAVE'

    channels = bits = rate = nil
    pos = 12
    while pos + 8 <= bytes.bytesize
      id = bytes.byteslice(pos, 4)
      size = bytes.byteslice(pos + 4, 4).unpack1('V')
      body = pos + 8
      if id == 'fmt '
        _format, channels, rate, _byte_rate, _align, bits = bytes.byteslice(body, 16).unpack('vvVVvv')
      elsif id == 'data'
        raise "fluidsynth wrote #{bits}-bit audio" unless bits == 16
        raise "fluidsynth wrote #{rate} Hz, not #{SAMPLE_RATE}" unless rate == SAMPLE_RATE

        frames = bytes.byteslice(body, [size, bytes.bytesize - body].min).unpack('s<*')
        return frames.each_slice(channels).map { |frame| frame.sum / (32_768.0 * channels) }
      end
      pos = body + size + (size.odd? ? 1 : 0)
    end
    raise 'fluidsynth wrote no audio'
  end
end
