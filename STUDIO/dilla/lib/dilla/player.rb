# frozen_string_literal: true

# ------------------------------------------------------------------ player
# Raw 16-bit mono PCM written to the stdin of a player. The player is an argv, never a shell
# string; a pipe that closes under us (the listener quit the player) ends the show quietly and
# does not raise.
class Player
  FFPLAY = ['/opt/homebrew/bin/ffplay', '/usr/local/bin/ffplay', '/usr/bin/ffplay'].freeze
  SOX = ['/opt/homebrew/bin/play', '/usr/local/bin/play', '/usr/bin/play'].freeze

  # The player: --player's command split into words, else ffplay, else sox's play.
  def self.command(options, rate = SAMPLE_RATE)
    channels = options[:mono] ? 1 : 2
    return Shellwords.split(options[:player]) if options[:player]

    ffplay = FFPLAY.find { |path| File.executable?(path) } || which('ffplay')
    return [ffplay, '-nodisp', '-autoexit', '-loglevel', 'quiet', '-f', 's16le', '-ar', rate.to_s, '-ac', channels.to_s, '-i', '-'] if ffplay

    play = SOX.find { |path| File.executable?(path) } || which('play')
    return [play, '-q', '-t', 'raw', '-r', rate.to_s, '-e', 'signed', '-b', '16', '-c', channels.to_s, '-'] if play

    abort 'No player: install ffplay or sox, or name one with --player (it reads raw 16-bit mono PCM on stdin)'
  end

  def self.which(name) = ENV.fetch('PATH', '').split(File::PATH_SEPARATOR).map { |dir| File.join(dir, name) }.find { |path| File.executable?(path) }

  # 16-bit little-endian samples, clipped; a stereo frame ([left, right]) is interleaved.
  def self.pcm(samples)
    samples = Stereo.interleave(samples) if samples.first.is_a?(Array)
    samples.map { |s| (s * 32_767).round.clamp(-32_768, 32_767) }.pack('s<*')
  end

  attr_reader :bytes

  def initialize(argv)
    @io = IO.popen(argv, 'wb')
    @pid = @io.pid
    @open = true
    @bytes = 0
  end

  def open? = @open

  # Hand over a block; false when the player has gone.
  def write(samples)
    return false unless @open

    data = Player.pcm(samples)
    @io.write(data)
    @io.flush
    @bytes += data.bytesize
    true
  rescue Errno::EPIPE, IOError
    @open = false
  end

  # End the input, give the player a moment to play out what it holds, then stop it.
  def finish(grace: 5.0)
    @io.close unless @io.closed?
  rescue Errno::EPIPE, IOError
    nil
  ensure
    @open = false
    wait(grace)
  end

  # Tell the player to stop, from a signal handler: nothing is waited for, and a write that is
  # blocked on a full pipe fails with EPIPE and so comes back.
  def interrupt
    Process.kill('TERM', @pid)
  rescue Errno::ESRCH
    nil
  end

  # Stop now.
  def kill
    @open = false
    Process.kill('TERM', @pid)
  rescue Errno::ESRCH
    nil
  ensure
    begin
      @io.close unless @io.closed?
    rescue Errno::EPIPE, IOError
      nil
    end
    wait(2.0)
  end

  private

  def wait(grace)
    Timeout.timeout(grace) { Process.wait(@pid) }
  rescue Timeout::Error
    begin
      Process.kill('KILL', @pid)
      Process.wait(@pid)
    rescue Errno::ESRCH, Errno::ECHILD
      nil
    end
  rescue Errno::ECHILD
    nil
  end
end
