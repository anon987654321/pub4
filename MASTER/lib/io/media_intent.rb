# frozen_string_literal: true

require "fileutils"
require "shellwords"
require "time"
require_relative "../boot/paths"
require_relative "script_dispatch"
require_relative "constraint_dsl"

module Master
  module Io
    # Routes a plainly spoken creative request to the local, consented media tools.
    # It is deliberately narrow: ordinary discussion of artists remains a chat turn.
    module MediaIntent
      module_function

      # Finished media lands in the user's home directory, not the repo.
      MEDIA_OUTPUT_DIR = File.expand_path("~")

      IMAGE_RE = /\b(?:make|create|generate|render|photograph|photo|portrait|image|picture)\b/i.freeze
      AUDIO_RE = /\b(?:make|create|generate|compose|render)\b.*\b(?:beat|loop|instrumental|track|music)\b|\b(?:dilla|j dilla|fly(?:ing)?\s+lotus|madlib|bach|baroque)\b.*\b(?:beat|loop|instrumental|track|music)\b/i.freeze
      KICK_RE = /\b(?:generate|create|make|render)\b.*\b(?:hard\s+hitting\s+)?(?:techno\s+)?kick\b/i.freeze
      SYNTH_RE = /\b(?:play|generate|create|make|render)\b.*\b(?:sine|square|triangle|saw|white|brown)\b.*\b(?:wave|noise|tone)\b/i.freeze
      # "Play" means the speakers and "make" means a file. A sentence that says
      # both ("make and play") gets the file, which it can then play.
      LIVE_RE = /\b(?:play|live|sound\s*card|speakers?)\b/i.freeze
      FILE_RE = /\b(?:make|render|generate|create|save|write|export)\b/i.freeze
      # "play it", "play that on my sound card": the last thing rendered.
      PLAY_LAST_RE = /\A\s*(?:please\s+)?(?:re)?play\s+(?:it|that|this|the\s+(?:last|file|wav|render|track|beat))\b/i.freeze
      # The live synthesiser is dilla's instrument, and so is its vocabulary:
      # these only recognise a sentence addressed to it and hand the sentence
      # over whole (`dilla.rb live say`), where the patches, progressions and
      # knobs it names are read.
      # An instrument needs a musical verb and a knob needs a knob verb, so
      # "open the patch" and "turn the lead into a test" stay chat.
      LIVE_SYNTH_PLAY_RE = /\b(?:play|morph\w*|fade|switch|jam)\b.*\b(?:(?:mini)?moog|model\s*d|prophet|rhodes|juno|synth\w*|pads?|lead|bass(?:line)?|brass|strings|flute|pluck|lo-?fi|chords?|progressions?|something)\b/i.freeze
      LIVE_SYNTH_KNOB_RE = /\b(?:open|close|sweep|raise|lower|turn)\b.*\b(?:filter|cutoff|resonance|emphasis|detune|contour)\b/i.freeze
      LIVE_SYNTH_ALONE_RE = /\A\s*(?:stop|silence|enough)\b|\bstop\s+(?:the\s+)?(?:music|playing|synth\w*|improvi\w*|jam)\b|\b(?:improvi[sz]e|keep\s+playing)\b|\A\s*(?:please\s+)?play(?:\s+(?:some\s+)?music)?\s*[.!]?\s*\z/i.freeze
      POSTPRO_RE = /\b(?:post-?process|colour\s+grade|color\s+grade|film\s+look|vhs(?:\s+tape)?\s+look|crt(?:\s+broadcast)?\s+look|camcorder(?:\s+glitch)?\s+look|make\s+this\s+(?:cinematic|analog|analogue))\b/i.freeze
      IMAGE_PATH_RE = /(?:["']([^"']+\.(?:jpe?g|png|webp|tiff?))["']|(?:\A|\s)([^\s"']+\.(?:jpe?g|png|webp|tiff?))(?=\z|\s))/i.freeze

      def handles?(text)
        text.match?(KICK_RE) || text.match?(PLAY_LAST_RE) || text.match?(SYNTH_RE) || live_synth?(text) ||
          text.match?(AUDIO_RE) || text.match?(POSTPRO_RE) ||
          text.match?(IMAGE_RE) && text.match?(/\b(?:photo|portrait|image|picture)\b/i)
      end

      def dispatch(text, root: MasterPaths.root)
        return generate_kick(text, root:) if text.match?(KICK_RE)
        return play_last(text, root:) if text.match?(PLAY_LAST_RE)
        return generate_tone(text, root:) if text.match?(SYNTH_RE)
        return live_synth(text, root:) if live_synth?(text)
        return postprocess(text, root:) if text.match?(POSTPRO_RE)
        return generate_beat(text, root:) if text.match?(AUDIO_RE)

        generate_cloud_image(text, root:)
      end

      def generate_cloud_image(prompt, root:)
        output = File.join(MEDIA_OUTPUT_DIR, "preprompt-#{Time.now.utc.strftime('%Y%m%dT%H%M%SZ')}.webp")
        args = ["generate", "--prompt", prompt, "--output", output]
        result = ScriptDispatch.run(root:, tool: "preprompt", arg: args.map { |v| Shellwords.escape(v) }.join(" "))
        result.ok? ? Result.ok({ output: result.value!, rendered: result.value!, media: :preprompt, path: output }) : result
      end

      def postprocess(text, root:)
        source = text.match(IMAGE_PATH_RE)&.captures&.compact&.first
        return Result.err("postpro: include an existing JPG, PNG, WebP, or TIFF path", category: :validation) if source.to_s.empty?

        source = File.expand_path(source)
        return Result.err("postpro: input not found #{source}", category: :validation) unless File.file?(source)

        preset = postpro_preset_for(text)
        output_dir = MEDIA_OUTPUT_DIR
        FileUtils.mkdir_p(output_dir)
        ext = File.extname(source)
        output = File.join(output_dir, "#{File.basename(source, ext)}-#{preset}#{ext}")

        args = ["--input", source, "--output", output, "--preset", preset]
        result = ScriptDispatch.run(root:, tool: "postpro", arg: args.map { |value| Shellwords.escape(value) }.join(" "))
        result.ok? ? Result.ok({ output: result.value!, rendered: result.value!, media: :postpro, path: output }) : result
      end

      SYNTH_SHAPES = {
        "sine" => :sine,
        "square" => :square,
        "triangle" => :triangle,
        "saw" => :saw,
        "white noise" => :white,
        "white wave" => :white,
        "brown noise" => :brown,
        "brown wave" => :brown,
      }.freeze

      def synth_shape_for(text)
        needle = text.to_s.downcase
        SYNTH_SHAPES.each do |word, shape|
          return shape if needle.include?(word)
        end
        nil
      end

      def generate_tone(text, root: MasterPaths.root)
        shape = synth_shape_for(text) || :sine
        hz = text.match?(/\b(?:deep|low|bass)\b/i) ? 110.0 : 440.0
        return play_tone(shape, hz) if text.match?(LIVE_RE) && !text.match?(FILE_RE)

        destination = File.join(MEDIA_OUTPUT_DIR, "master-#{shape}-#{Time.now.utc.strftime('%Y%m%dT%H%M%SZ')}.wav")
        result = Master::Music::Synth.render(shape:, hz:, destination:)
        Result.ok({ output: result, rendered: result, media: :synth, path: result })
      end

      LIVE_TONE_SECONDS = 3.0

      def play_tone(shape, hz)
        Master::Music::Realtime.play(shape:, hz:, seconds: LIVE_TONE_SECONDS)
        line = "played #{shape} at #{hz.round} Hz on the sound card for #{LIVE_TONE_SECONDS.round} s"
        Result.ok({ output: line, rendered: line, media: :synth_live })
      rescue Master::Music::AudioSink::NoPlayerError => e
        Result.err("#{e.message}: install sox (brew install sox) or ffmpeg, whose ffplay also plays", category: :infrastructure)
      end

      def live_synth?(text)
        [LIVE_SYNTH_ALONE_RE, LIVE_SYNTH_PLAY_RE, LIVE_SYNTH_KNOB_RE].any? { |pattern| text.match?(pattern) }
      end

      # dilla answers at once: a sentence that starts music leaves a player of
      # its own running and returns, one that steers or stops it sends the
      # word to that player.
      def live_synth(text, root: MasterPaths.root)
        result = ScriptDispatch.run(root:, tool: "dilla", arg: "live say #{Shellwords.escape(text)}")
        result.ok? ? Result.ok({ output: result.value!, rendered: result.value!, media: :dilla_live }) : result
      end

      # What this surface writes: tones and kicks as master-*.wav, beats as
      # <style>-<UTC stamp>.mp3.
      RENDERED_MEDIA = %w[master-*.wav *-2???????T??????Z.mp3].freeze

      def last_media(dir = MEDIA_OUTPUT_DIR)
        RENDERED_MEDIA.flat_map { |pattern| Dir.glob(File.join(dir, pattern)) }.max_by { |path| File.mtime(path) }
      end

      def play_last(_text, root: MasterPaths.root)
        path = last_media
        return Result.err("nothing rendered yet in #{MEDIA_OUTPUT_DIR}; ask for a sound first", category: :validation) unless path

        pid = Master::Music::Synth.play(path)
        line = "playing #{path} (pid #{pid})"
        Result.ok({ output: line, rendered: line, media: :playback, path: })
      rescue RuntimeError => e
        Result.err("#{e.message}: install sox (brew install sox) or ffmpeg for ffplay", category: :infrastructure)
      end

      def generate_kick(_text, root: MasterPaths.root)
        destination = File.join(MEDIA_OUTPUT_DIR, "master-techno-kick-#{Time.now.utc.strftime('%Y%m%dT%H%M%SZ')}.wav")
        result = Master::Music::KickLoop.render(destination:)
        Result.ok({ output: result, rendered: result, media: :kick_loop, path: result })
      end

      POSTPRO_PRESETS = [
        [/\bvhs\b/i, "vhs_tape"],
        [/\bcrt\b/i, "crt_broadcast"],
        [/\bcamcorder|mini\s*dv|hi\s*8\b/i, "camcorder_glitch"],
        [/\bportrait\b/i, "portrait"],
        [/\bnoir|black\s+and\s+white\b/i, "noir"],
        [/\blo[ -]?fi\b/i, "lo_fi"],
        [/\bmagic\s+hour|golden\s+hour\b/i, "magic_hour"],
      ].freeze

      def postpro_preset_for(text)
        POSTPRO_PRESETS.find { |pattern, _preset| text.match?(pattern) }&.last || "cinematic"
      end

      DEFAULT_BEAT_BARS = 12

      BEAT_STYLES = [
        [/\bbach|baroque\b/i, "baroque"],
        [/\bneo[ -]?soul\b/i, "neo-soul"],
        [/\bjazz\b/i, "jazz"],
        [/fly(?:ing)?\s+lotus/i, "flylo"],
      ].freeze

      def beat_style_for(text)
        BEAT_STYLES.find { |pattern, _style| text.match?(pattern) }&.last || "dilla"
      end

      def generate_beat(text, root:)
        # Use ConstraintDSL to resolve intent before rendering
        constraints = ConstraintDSL.parse_intent(text)
        resolved_params = ConstraintDSL.resolve(constraints)
        style = beat_style_for(text)

        output_dir = MEDIA_OUTPUT_DIR
        FileUtils.mkdir_p(output_dir)
        output = File.join(output_dir, "#{style}-#{Time.now.utc.strftime('%Y%m%dT%H%M%SZ')}.mp3")

        # Mirror Shared::DillaProcessor#run_script: the engine's CLI is
        # `dilla.rb dilla <output> <bars>` — style/track selection happens via
        # TRACK/PROGRESSION ENV, and resolved constraints now drive the renders.
        track = style.tr("-", "_")
        env = { "RENDER_MODE" => "dilla", "SPEAK" => "0" }

        # Merge resolved constraints into the environment for the dilla engine
        resolved_params.each { |k, v| env[k.to_s.upcase] = v.to_s }
        env.merge!("TRACK" => track, "PROGRESSION" => track) unless track == "dilla"

        args = ["dilla", output, DEFAULT_BEAT_BARS.to_s]
        result = ScriptDispatch.run(root:, tool: "dilla", arg: args.map { |v| Shellwords.escape(v) }.join(" "), env:)
        result.ok? ? Result.ok({ output: result.value!, rendered: result.value!, media: :dilla, path: output }) : result
      end
    end
  end
end
