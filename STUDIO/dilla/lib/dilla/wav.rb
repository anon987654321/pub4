# ---------------------------------------------------------------- WAV writer
module WAV
  # `samples` is a flat array for a mono file, or [left, right] for a stereo one. Sixteen bits by
  # default, or twenty-four; floats past full scale are clipped.
  def self.write(path, samples, bits: 16)
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

    File.binwrite(path, header + data)
  end

  # Bounded-memory output for long renders; never overwrites an existing take.
  def self.write_stream(path, frames:, channels:, bits: 16, block_size: 8192)
    raise ArgumentError, "frames must be positive" unless frames.is_a?(Integer) && frames.positive?
    raise ArgumentError, "channels must be one or two" unless [1, 2].include?(channels)
    raise ArgumentError, "bits must be 16 or 24" unless [16, 24].include?(bits)
    raise ArgumentError, "block size must be positive" unless block_size.is_a?(Integer) && block_size.positive?

    width = bits / 8
    header = +"RIFF" + [0].pack("V") + "WAVEfmt " + [16].pack("V") + [1].pack("v")
    header << [channels, SAMPLE_RATE, SAMPLE_RATE * width * channels, width * channels, bits].pack("vVVvv")
    header << "data" << [0].pack("V")
    created = false
    complete = false
    File.open(path, "wx+") do |file|
      created = true
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
      complete = true
    end
    path
  rescue StandardError
    File.delete(path) if created && !complete && File.file?(path)
    raise
  end

  # Three bytes a sample, least significant first.
  def self.pack24(flat)
    flat.map do |s|
      v = (s * 8_388_607).round.clamp(-8_388_608, 8_388_607)
      [v & 0xff, (v >> 8) & 0xff, (v >> 16) & 0xff].pack('C3')
    end.join
  end
end
