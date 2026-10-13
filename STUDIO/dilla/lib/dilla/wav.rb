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

  # Three bytes a sample, least significant first.
  def self.pack24(flat)
    flat.map do |s|
      v = (s * 8_388_607).round.clamp(-8_388_608, 8_388_607)
      [v & 0xff, (v >> 8) & 0xff, (v >> 16) & 0xff].pack('C3')
    end.join
  end
end
