# ---------------------------------------------------------------- WAV writer
module WAV
  # `samples` is a flat array for a mono file, or [left, right] for a stereo one.
  def self.write(path, samples)
    channels = samples.first.is_a?(Array) ? samples.size : 1
    data = (samples.first.is_a?(Array) ? Stereo.interleave(samples) : samples).map { |s| (s * 32767).round.clamp(-32_768, 32_767) }.pack('s<*')

    header  = +"RIFF"
    header << [36 + data.bytesize].pack('V')
    header << "WAVE"
    header << "fmt "
    header << [16].pack('V')
    header << [1].pack('v')                    # PCM
    header << [channels].pack('v')
    header << [SAMPLE_RATE].pack('V')
    header << [SAMPLE_RATE * 2 * channels].pack('V') # byte rate
    header << [2 * channels].pack('v')         # block align
    header << [16].pack('v')                   # bits per sample
    header << "data"
    header << [data.bytesize].pack('V')

    File.binwrite(path, header + data)
  end
end

