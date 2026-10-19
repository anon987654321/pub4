# ---------------------------------------------------------------- WAV writer
require "fileutils"
require "tempfile"

module WAV
  # Samples are mono or channel arrays; generated takes are immutable unless the
  # caller explicitly opts in to replacement.
  def self.write(path, samples, bits: 16, replace: false)
    channels = samples.first.is_a?(Array) ? samples.size : 1
    flat = samples.first.is_a?(Array) ? Stereo.interleave(samples) : samples
    data = bits == 24 ? pack24(flat) : flat.map { |s| (s * 32767).round.clamp(-32_768, 32_767) }.pack('s<*')
    width = bits / 8

    header  = +"RIFF"
    header << [36 + data.bytesize].pack('V')
    header << "WAVE"
    header << "fmt "
    header << [16].pack('V')
    header << [1].pack('v')                    # PCM
    header << [channels].pack('v')
    header << [SAMPLE_RATE].pack('V')
    header << [SAMPLE_RATE * width * channels].pack('V') # byte rate
    header << [width * channels].pack('v')     # block align
    header << [bits].pack('v')                 # bits per sample
    header << "data"
    header << [data.bytesize].pack('V')

    write_bytes(path, header + data, replace:)
  end

  # Stage in the destination directory and publish atomically. A hard link is
  # create-if-absent, unlike File.binwrite's silent truncation; rename is used
  # only for an explicit replace request. Failed writes leave the prior take intact.
  def self.write_bytes(path, bytes, replace: false)
    directory = File.dirname(path)
    FileUtils.mkdir_p(directory)
    previous_mode = File.file?(path) ? File.stat(path).mode & 0o7777 : nil
    mode = replace && previous_mode ? previous_mode : 0o666 & ~File.umask

    Tempfile.create(["studio-output-", ".tmp"], directory, binmode: true) do |tmp|
      tmp.write(bytes)
      tmp.flush
      tmp.fsync
      File.chmod(mode, tmp.path)
      tmp.close
      replace ? File.rename(tmp.path, path) : File.link(tmp.path, path)
    end
    path
  rescue Errno::EEXIST
    raise ArgumentError, "refusing to overwrite existing take: #{path}; choose a new path or pass --replace"
  end

  # Bounded-memory output for long renders; never overwrites an existing take.
  # Bounded-memory output published atomically. The final path appears only after
  # every block and the RIFF sizes have been written and synced; a crash or an
  # invalid block can leave a temporary file only, never a plausible partial WAV.
  def self.write_stream(path, frames:, channels:, bits: 16, block_size: 8192)
    raise ArgumentError, "frames must be positive" unless frames.is_a?(Integer) && frames.positive?
    raise ArgumentError, "channels must be one or two" unless [1, 2].include?(channels)
    raise ArgumentError, "bits must be 16 or 24" unless [16, 24].include?(bits)
    raise ArgumentError, "block size must be positive" unless block_size.is_a?(Integer) && block_size.positive?

    destination = File.expand_path(path.to_s)
    directory = File.dirname(destination)
    FileUtils.mkdir_p(directory)

    width = bits / 8
    header = +"RIFF" + [0].pack("V") + "WAVEfmt " + [16].pack("V") + [1].pack("v")
    header << [channels, SAMPLE_RATE, SAMPLE_RATE * width * channels, width * channels, bits].pack("vVVvv")
    header << "data" << [0].pack("V")

    Tempfile.create(["studio-output-", ".tmp"], directory, binmode: true) do |file|
      file.write(header)
      offset = 0
      while offset < frames
        count = [block_size, frames - offset].min
        channel_data = yield(offset, count)
        unless channel_data.is_a?(Array) && channel_data.length == channels &&
               channel_data.all? { |values| values.is_a?(Array) && values.length == count }
          raise ArgumentError, "audio block must contain #{channels} channels by #{count} frames"
        end

        flat = channels == 1 ? channel_data.fetch(0) : Stereo.interleave(channel_data)
        bytes = bits == 24 ? pack24(flat) : flat.map { |sample| (sample * 32_767).round.clamp(-32_768, 32_767) }.pack("s<*")
        file.write(bytes)
        offset += count
      end

      data_size = file.size - 44
      raise ArgumentError, "WAV exceeds RIFF size limit" if data_size > 0xffff_ffff - 36
      file.seek(4)
      file.write([36 + data_size].pack("V"))
      file.seek(40)
      file.write([data_size].pack("V"))
      file.flush
      file.fsync
      File.chmod(0o666 & ~File.umask, file.path)
      file.close

      # A hard link is an atomic create-if-absent publish. It does not silently
      # replace an earlier take and cannot expose the temporary WAV's old header.
      File.link(file.path, destination)
    end
    path
  end

  # Three bytes a sample, least significant first.
  def self.pack24(flat)
    flat.map do |s|
      v = (s * 8_388_607).round.clamp(-8_388_608, 8_388_607)
      [v & 0xff, (v >> 8) & 0xff, (v >> 16) & 0xff].pack('C3')
    end.join
  end
end
