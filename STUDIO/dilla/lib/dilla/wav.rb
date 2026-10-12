# ---------------------------------------------------------------- WAV writer
module WAV
  def self.write(path, samples)
    data = samples.map { |s| (s * 32767).round.clamp(-32_768, 32_767) }.pack('s<*')

    header  = +"RIFF"
    header << [36 + data.bytesize].pack('V')
    header << "WAVE"
    header << "fmt "
    header << [16].pack('V')
    header << [1].pack('v')                    # PCM
    header << [1].pack('v')                    # mono
    header << [SAMPLE_RATE].pack('V')
    header << [SAMPLE_RATE * 2].pack('V')      # byte rate
    header << [2].pack('v')                    # block align
    header << [16].pack('v')                   # bits per sample
    header << "data"
    header << [data.bytesize].pack('V')

    File.binwrite(path, header + data)
  end
end

