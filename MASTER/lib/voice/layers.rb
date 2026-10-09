# frozen_string_literal: true

module Master
  module Voice
    # What a voice profile adds beyond the -af chain, which cannot synthesize a
    # second input: a breath before the utterance, a pause after it, a whisper
    # bed that follows the speech envelope, and width from a short delay on one
    # channel. Every noise source is seeded, so the same sentence renders the
    # same way. Policy.layers declares the numbers. This builds the ffmpeg
    # command and runs it, and a failure returns false so Speech#shaped keeps
    # the sentence it already has.
    module Layers
      RATE = 24_000
      FLOAT_STEREO = "aformat=sample_fmts=fltp:sample_rates=#{RATE}:channel_layouts=stereo".freeze

      module_function

      def active? = !Policy.layers.empty?

      def apply(input, output)
        seconds = duration(input)
        return false unless seconds

        argv = command(input:, output:, chain: Policy.post_chain, seconds:)
        _out, _err, status = Master::Io::Exec.capture3(*argv)
        status.success? && File.size?(output) ? true : false
      end

      def command(input:, output:, chain:, seconds:)
        cfg = Policy.layers
        whisper = cfg["whisper"]
        breath = cfg["breath"]
        noise = whisper ? Array(whisper["seeds"]).first(2).map { |seed| noise_source(seed, seconds + pause(cfg)) } : []
        noise << noise_source(breath.fetch("seed"), breath.fetch("ms") / 1000.0) if breath
        graph = [dry(cfg, chain, whisper), *whisper_bed(whisper), mix(whisper), finish(breath, noise.size)]
        ["ffmpeg", "-y", "-i", input, *noise.flat_map { |source| ["-f", "lavfi", "-i", source] },
         "-filter_complex", graph.flatten.compact.join(";"), "-map", "[out]", "-ac", "2", output]
      end

      def duration(path)
        out, _err, status = Master::Io::Exec.capture3(
          "ffprobe", "-v", "error", "-show_entries", "format=duration", "-of", "csv=p=0", path
        )
        seconds = out.to_f
        status.success? && seconds.positive? ? seconds : nil
      end

      # White, because both consumers band-limit it first and white leaves about
      # 8 dB more of the band than pink does: measured against a Jenny sentence,
      # that is the difference between a whisper 23 dB under the voice and one
      # at the 14 dB the profile declares.
      def noise_source(seed, seconds)
        "anoisesrc=c=white:r=#{RATE}:a=0.5:seed=#{seed}:d=#{format('%.3f', seconds)}"
      end

      def pause(cfg) = cfg.fetch("pause_ms", 0).to_f / 1000

      def dry(cfg, chain, whisper)
        head = "[0:a]aformat=sample_rates=#{RATE}:channel_layouts=mono,#{chain || 'anull'}"
        # 0.707 per channel: the same voice in two channels would read louder
        # than in one, and how loud MASTER is belongs to the operator.
        side = "pan=stereo|c0=0.707*c0|c1=0.707*c0,adelay=0|#{cfg.fetch('width_ms', 0).to_i}," \
               "apad=pad_dur=#{format('%.3f', pause(cfg))}"
        whisper ? "#{head},asplit=2[dm][de];[dm]#{side}[dry]" : "#{head},#{side}[dry]"
      end

      # The envelope of the dry voice shapes decorrelated stereo noise, so the
      # whisper breathes with the speech and is silent where it is.
      def whisper_bed(whisper)
        return [] unless whisper

        low, high = whisper.fetch("band_hz")
        [
          "[de]aeval=abs(val(0)):c=same,lowpass=f=#{whisper.fetch('smoothing_hz')}," \
          "volume=#{whisper.fetch('boost_db')}dB,pan=stereo|c0=c0|c1=c0,#{FLOAT_STEREO}[env]",
          "[1:a][2:a]amerge=inputs=2,highpass=f=#{low},lowpass=f=#{high},#{FLOAT_STEREO}[nz]",
          "[nz][env]amultiply,volume=#{whisper.fetch('gain_db')}dB[wh]",
        ]
      end

      def mix(whisper)
        return "[dry]#{FLOAT_STEREO}[mix]" unless whisper

        "[dry][wh]amix=inputs=2:duration=first:normalize=0,#{FLOAT_STEREO}[mix]"
      end

      # The breath-in leads the utterance, so its source is the last input.
      def finish(breath, last_input)
        return "[mix]anull[out]" unless breath

        [
          "#{breath_filter(breath, last_input)}[br]",
          "[br][mix]concat=n=2:v=0:a=1[out]",
        ]
      end

      # One breath-in from a white noise input, band-limited and faded in over
      # the first 42 percent and out over the rest. The human profile reuses it
      # in mono before a long sentence.
      def breath_filter(breath, input, stereo: true)
        low, high = breath.fetch("band_hz")
        rise = (breath.fetch("ms") * 0.42 / 1000).round(3)
        fall = (breath.fetch("ms") * 0.58 / 1000).round(3)
        tail = stereo ? "pan=stereo|c0=c0|c1=c0,#{FLOAT_STEREO}" : "aformat=sample_fmts=fltp:sample_rates=#{RATE}:channel_layouts=mono"
        "[#{input}:a]bandpass=f=#{Math.sqrt(low * high).round}:width_type=h:w=#{high - low}," \
          "afade=t=in:d=#{rise},afade=t=out:st=#{rise}:d=#{fall},volume=#{breath.fetch('gain_db')}dB,#{tail}"
      end
    end
  end
end
