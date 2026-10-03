# frozen_string_literal: true

require "fileutils"

module Master
  module Music
    # Minimal PCM WAV writer shared by MASTER's native synthesis.
    module Waveform
      module_function

      def write_wav(destination, samples, rate: 44_100)
        FileUtils.mkdir_p(File.dirname(destination))
        pcm = samples.map { |sample| (sample.clamp(-1.0, 1.0) * 32_767).round }.pack("s<*")
        data_size = pcm.bytesize
        byte_rate = rate * 2
        block_align = 2
        bits_per_sample = 16
        header = "RIFF" + [36 + data_size].pack("V") + "WAVE" +
                 "fmt " + [16].pack("V") + [1].pack("v") + [1].pack("v") +
                 [rate].pack("V") + [byte_rate].pack("V") +
                 [block_align].pack("v") + [bits_per_sample].pack("v") +
                 "data" + [data_size].pack("V")
        File.binwrite(destination, header + pcm)
        destination
      end
    end
  end
end
