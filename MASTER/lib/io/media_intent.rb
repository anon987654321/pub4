# frozen_string_literal: true

require "fileutils"
require "shellwords"
require "time"
require_relative "../boot/paths"
require_relative "script_dispatch"
require_relative "constraint_dsl"
require_relative "natural_intent"

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
      LIVE_MUSIC_RE = /\b(?:play|start|resume|put on|queue)\b.*\b(?:liveset|default\s+music)\b/i.freeze
      LIVE_AUDIO_STOP_RE = /\b(?:stop|kill|silence|mute|shut\s+off)\b.*\b(?:music|playing|sound|audio|synth\w*|liveset|jam)\b|\b(?:music|playing|sound|audio|synth\w*|liveset)\b.*\b(?:stop|kill|silence|mute|shut\s+off)\b/i.freeze
      LIVE_STYLE_RE = /\b(?:röyksopp|royksopp|melody\s+a\.m\.)\b/i.freeze
      LIVE_STYLE_VERB_RE = /\b(?:play|start|resume|switch|change|move|go|use|put\s+on|queue)\b|\b(?:sound\s*card|speakers?)\b/i.freeze
      BACKGROUND_MUSIC_RE = /\b(?:play|start|resume|put on|queue)\b.*\b(?:your|some|the|my)?\s*music\b.*\bbackground\b/i.freeze
      LIVE_SYNTH_ALONE_RE = /\A\s*(?:stop|silence|enough)\b|\bstop\s+(?:the\s+)?(?:music|playing|synth\w*|improvi\w*|jam)\b|\b(?:improvi[sz]e|keep\s+playing)\b|\A\s*(?:please\s+)?play(?:\s+(?:some\s+)?music)?\s*[.!]?\s*\z/i.freeze
      POSTPRO_COMMAND_RE = /\b(?:run|use|call|invoke)\s+postpro(?:\.rb)?\b/i.freeze
      POSTPRO_RE = /\b(?:post-?process|colour\s+grade|color\s+grade|film\s+look|vhs(?:\s+tape)?\s+look|crt(?:\s+broadcast)?\s+look|camcorder(?:\s+glitch)?\s+look|make\s+this\s+(?:cinematic|analog|analogue))\b/i.freeze
      IMAGE_PATH_RE = /(?:["']([^"']+\.(?:jpe?g|png|webp|tiff?))["']|(?:\A|\s)([^\s"']+\.(?:jpe?g|png|webp|tiff?))(?=\z|\s))/i.freeze
      POSTPRO_SUBJECT_RE = /\bpostpro(?:\.rb)?\b.*?\b(?:over|on|in|for|from)\b\s+["']([^"']+)["']/i.freeze
      POSTPRO_SUBJECT_TOKEN_RE = /\bpostpro(?:\.rb)?\b.*?\b(?:over|on|in|for|from)\b\s+(?:these|the|my|new)?\s*(?:photos?|images?|pictures?|files?)?\s*(?:in|at|from|under)?\s*(~?(?:\/|\.\/|\.\.\/)?[^\s"']+\/?)(?=\z|\s)/i.freeze
      POSTPRO_PATH_TOKEN_RE = /\b(?:in|at|from|under)\s+(~?(?:\/|\.\/|\.\.\/)[^\s"']+\/?)(?=\z|\s)/i.freeze
      DESKTOP_RE = /\b(?:my\s+|the\s+)?(?:local\s+)?desktop(?:\s+folder)?\b/i.freeze
      POSTPRO_RANDOM_RE = /\b(?:random|randomly|variations?|versions?)\b/i.freeze
      POSTPRO_EXTREME_RE = /\b(?:extreme|wild|aggressive|rough)\b/i.freeze

      def handles?(text)
        text.match?(KICK_RE) || text.match?(PLAY_LAST_RE) || text.match?(SYNTH_RE) || text.match?(LIVE_AUDIO_STOP_RE) || live_synth?(text) ||
          text.match?(BACKGROUND_MUSIC_RE) || text.match?(AUDIO_RE) || postpro_intent?(text) ||
          text.match?(IMAGE_RE) && text.match?(/\b(?:photo|portrait|image|picture)\b/i)
      end

      def dispatch(text, root: MasterPaths.root)
        return generate_kick(text, root:) if text.match?(KICK_RE)
        return play_last(text, root:) if text.match?(PLAY_LAST_RE)
        return generate_tone(text, root:) if text.match?(SYNTH_RE)
        return stop_live_audio(root:) if text.match?(LIVE_AUDIO_STOP_RE)
        return live_synth(text, root:) if live_synth?(text)
        return play_background_music(root:) if text.match?(BACKGROUND_MUSIC_RE)
        return postprocess(text, root:) if postpro_intent?(text)
        return generate_beat(text, root:) if text.match?(AUDIO_RE)

        generate_cloud_image(text, root:)
      end

      def postpro_intent?(text)
        parsed = NaturalIntent.resolve(text)
        return true if parsed&.intent == :postprocess

        text.match?(POSTPRO_COMMAND_RE) || text.match?(POSTPRO_RE)
      end

      def generate_cloud_image(prompt, root:)
        output = File.join(MEDIA_OUTPUT_DIR, "replicate-#{Time.now.utc.strftime('%Y%m%dT%H%M%SZ')}.webp")
        args = ["generate", "--prompt", prompt, "--output", output]
        result = ScriptDispatch.run(root:, tool: "replicate", arg: args.map { |v| Shellwords.escape(v) }.join(" "))
        result.ok? ? Result.ok({ output: result.value!, rendered: result.value!, media: :replicate, path: output }) : result
      end

      def postprocess(text, root:)
        intent = NaturalIntent.resolve(text)
        entities = intent&.entities || {}
        downloads = entities[:location] == "downloads" ||
                    text.match?(/\b(?:my\s+|the\s+)?(?:local\s+)?downloads?(?:\s+folder)?\b/i)
        source = downloads_directory if downloads
        return Result.err("postpro: Downloads folder not found", category: :validation) if downloads && source.to_s.empty?
        desktop = text.match?(DESKTOP_RE)
        source = desktop_directory if desktop
        return Result.err("postpro: Desktop folder not found", category: :validation) if desktop && source.to_s.empty?
        source ||= entities[:path]
        source ||= text.match(POSTPRO_SUBJECT_RE)&.captures&.first
        source ||= text.match(POSTPRO_SUBJECT_TOKEN_RE)&.captures&.first
        source ||= text.match(POSTPRO_PATH_TOKEN_RE)&.captures&.first
        source ||= text.match(IMAGE_PATH_RE)&.captures&.compact&.first
        return Result.err("postpro: include an existing image file or directory path", category: :validation) if source.to_s.empty?

        if source.to_s.match?(/[*?\[\]{}]/)
          files = image_glob_files(source)
          return run_postpro_random(files, text, root:) if postpro_random_request?(text)
          return run_postpro_selection(files, text, root:) unless files.empty?
          return Result.err("postpro: glob matched no images #{File.expand_path(source)}", category: :validation)
        end

        source = File.expand_path(source)
        return Result.err("postpro: input not found #{source}", category: :validation) unless File.file?(source) || File.directory?(source)

        if File.directory?(source) && postpro_random_request?(text)
          return run_postpro_random(source, text, root:)
        end

        selection = postpro_selection(text, source, intent:)
        return run_postpro_selection(selection[:files], text, root:) if selection
        return run_postpro_file(source, text, root:) if File.file?(source)

        args = [source]
        result = ScriptDispatch.run(root:, tool: "postpro",
                                    arg: args.map { |value| Shellwords.escape(value) }.join(" "))
        result.ok? ? Result.ok({ output: result.value!, rendered: result.value!, media: :postpro, path: source }) : result
      end

      def desktop_directory
        [
          File.expand_path("~/Desktop"),
          File.expand_path("~/desktop")
        ].find { |path| File.directory?(path) }
      end

      def downloads_directory
        [
          File.expand_path("~/Downloads"),
          File.expand_path("~/downloads"),
          File.expand_path("~/storage/downloads"),
          "/sdcard/Download"
        ].find { |path| File.directory?(path) }
      end

      def postpro_selection(text, source, intent: NaturalIntent.resolve(text))
        return unless File.directory?(source)

        entities = intent&.entities || {}
        recent = %w[latest recent].include?(entities[:recency].to_s)
        count = entities[:count].to_i if entities[:count]
        count = recent_count_default if recent && (!count || count <= 0)
        count = text.match(/\b(\d+)\s+(?:latest|newest|most\s+recent)\b/i)&.captures&.first&.to_i if (!count || count <= 0)
        return if !recent && (!count || count <= 0)

        extension = entities[:file_type]
        extension ||= text.match(/\b(jpe?g|png|webp|tiff?)s?\b/i)&.captures&.first
        files = Dir.glob(File.join(source, "**", "*"), File::FNM_DOTMATCH).select do |path|
          next false unless File.file?(path)
          next false if extension && File.extname(path).delete_prefix(".").downcase != extension.downcase.sub("jpeg", "jpg")
          path.match?(/\.(?:jpe?g|png|webp|tiff?)\z/i)
        end
        files.sort_by { |path| -File.mtime(path).to_f }.first([count, 24].min).then { |rows| { files: rows } }
      rescue StandardError
        { files: [] }
      end

      def image_glob_files(pattern)
        Dir.glob(File.expand_path(pattern)).select do |path|
          File.file?(path) && path.match?(/\.(?:jpe?g|png|webp|tiff?)\z/i)
        end
      rescue StandardError
        []
      end

      def postpro_random_request?(text)
        text.match?(POSTPRO_RANDOM_RE)
      end

      def postpro_random_count(text)
        text.match(/\b(\d+)\s+(?:random\s+)?(?:variations?|versions?|images?|photos?)\b/i)&.captures&.first.to_i.clamp(1, 24).tap do |count|
          return count if count.positive?
        end
        recent_count_default
      end

      def run_postpro_random(source, text, root:)
        count = postpro_random_count(text)
        subject = if source.is_a?(Array)
                    File.dirname(source.first)
                  else
                    source
                  end
        command = [subject, "--random", "--count", count.to_s].map { |value| Shellwords.escape(value) }
        command << "--rough" if text.match?(POSTPRO_EXTREME_RE)
        result = ScriptDispatch.run(root:, tool: "postpro", arg: command.join(" "))
        return result unless result.ok?

        rendered = result.value!.to_s
        Result.ok(output: rendered, rendered:, media: :postpro_random,
                  paths: source.is_a?(Array) ? source : nil)
      end

      def stop_live_audio(root: MasterPaths.root)
        Voice::Playback.interrupt!("operator requested audio stop") if defined?(Voice::Playback)
        result = ScriptDispatch.run(root:, tool: "dilla", arg: "live stop")
        return result unless result.ok?

        Result.ok({ output: result.value!, rendered: result.value!, media: :dilla_stop })
      end

      def recent_count_default
        config = Master.patterns_config["media"]
        Integer(config.dig("postprocess", "recent_count") || 5)
      rescue StandardError
        5
      end

      def run_postpro_selection(files, text, root:)
        return Result.err("postpro: no matching images found", category: :validation) if files.empty?

        results = files.map { |source| run_postpro_file(source, text, root:) }
        failure = results.find(&:err?)
        return failure if failure

        output = results.map { |result| result.value![:rendered].to_s }.join("\n")
        rendered = ["postpro: processed #{files.size} images", output].reject(&:empty?).join("\n")
        Result.ok(output: rendered, rendered:, media: :postpro_batch, paths: files)
      end

      def run_postpro_file(source, text, root:)
        preset = postpro_preset_for(text)
        output_dir = MEDIA_OUTPUT_DIR
        FileUtils.mkdir_p(output_dir)
        ext = File.extname(source)
        output = File.join(output_dir, "#{File.basename(source, ext)}-#{preset}#{ext}")
        args = ["--input", source, "--output", output, "--preset", preset]
        result = ScriptDispatch.run(root:, tool: "postpro", arg: args.map { |value| Shellwords.escape(value) }.join(" "))
        return result unless result.ok?

        rendered = result.value!.to_s
        Result.ok(output: rendered, rendered:, media: :postpro, path: output)
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
        return play_tone(shape, hz, duration_for(text)) if text.match?(LIVE_RE) && !text.match?(FILE_RE)

        destination = File.join(MEDIA_OUTPUT_DIR, "master-#{shape}-#{Time.now.utc.strftime('%Y%m%dT%H%M%SZ')}.wav")
        result = Master::Music::Synth.render(shape:, hz:, destination:)
        Result.ok({ output: result, rendered: result, media: :synth, path: result })
      end

      LIVE_TONE_SECONDS = 3.0

      def duration_for(text)
        seconds = text.match(/\b(?:for\s+)?(\d+(?:\.\d+)?)\s*(?:seconds?|secs?|s)\b/i)&.captures&.first
        seconds ? seconds.to_f.clamp(0.1, 300.0) : LIVE_TONE_SECONDS
      end

      def play_tone(shape, hz, seconds)
        Master::Music::Realtime.play(shape:, hz:, seconds:)
        line = "played #{shape} at #{hz.round} Hz on the sound card for #{seconds.to_s.sub(/\.0\z/, '')} s"
        Result.ok({ output: line, rendered: line, media: :synth_live })
      rescue Master::Music::AudioSink::NoPlayerError => e
        Result.err("#{e.message}: install sox (brew install sox) or ffmpeg, whose ffplay also plays", category: :infrastructure)
      end

      def live_synth?(text)
        [LIVE_MUSIC_RE, LIVE_SYNTH_ALONE_RE, LIVE_SYNTH_PLAY_RE, LIVE_SYNTH_KNOB_RE].any? { |pattern| text.match?(pattern) } ||
          (text.match?(LIVE_STYLE_RE) && text.match?(LIVE_STYLE_VERB_RE))
      end

      def repeatable?(text)
        text.match?(PLAY_LAST_RE) ||
          text.match?(LIVE_MUSIC_RE) ||
          text.match?(SYNTH_RE) && text.match?(LIVE_RE) && !text.match?(FILE_RE) ||
          live_synth?(text) && text.match?(LIVE_RE)
      end

      # dilla answers at once: a sentence that starts music leaves a player of
      # its own running and returns, one that steers or stops it sends the
      # word to that player.
      def play_background_music(root: MasterPaths.root)
        result = ScriptDispatch.run(root:, tool: "dilla", arg: "live default")
        return result unless result.ok?

        Result.ok({ output: result.value!, rendered: result.value!, media: :dilla_background })
      end

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

      def postpro_preset_for(text)
        NaturalIntent.resolve(text)&.entities&.fetch(:preset, nil) || "cinematic"
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
