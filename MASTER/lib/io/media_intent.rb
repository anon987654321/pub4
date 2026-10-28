# frozen_string_literal: true

require "fileutils"
require "json"
require "shellwords"
require "time"
require_relative "../boot/paths"
require_relative "../../contracts/studio"
require_relative "script_dispatch"
require_relative "natural_intent"
require_relative "lora_intent"

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
      REFERENCE_AUDIO_RE = /\b(?:analy[sz]e|analy[sz]ing|study|learn from|break down|separate|split|extract|inspect|understand|teach|model|use as (?:a )?reference|reference(?: (?:track|song|audio))?|listen to|here(?:'s| is)|this is how|use this|inspired by|learn the sound of)\b/i.freeze
      REFERENCE_STYLE_RE = /\b(?:j\s*dilla|dilla|slum\s+village|boom[ -]?bap|hip[ -]?hop|industrial[ -]?techno|techno|general|generic|neutral|style[ -]?agnostic)\b|\bfantastic,?\s+vol(?:ume)?\.?\s*2\b/i.freeze
      REFERENCE_GENERAL_RE = /\b(?:general|generic|neutral|unclassified|style[ -]?agnostic|without (?:a )?(?:style|genre) hint|do not infer (?:a )?(?:style|genre))\b/i.freeze
      REFERENCE_URL_RE = /https?:\/\/(?:(?:www|m|music)\.)?(?:youtu\.be\/[A-Za-z0-9_-]{11}|youtube\.com\/(?:watch\?(?:[^&#\s]*&)*v=[A-Za-z0-9_-]{11}|shorts\/[A-Za-z0-9_-]{11}|embed\/[A-Za-z0-9_-]{11}|live\/[A-Za-z0-9_-]{11}|v\/[A-Za-z0-9_-]{11}))[^\s<>"'\]\)]*/i.freeze
      REFERENCE_SOURCE_LIMIT = 5
      # Album-length analysis is opt-in through explicit album wording; ordinary track URLs retain the 15-minute default.
      REFERENCE_ALBUM_RE = /\b(?:full\s+album|album(?:-length)?|lp)\b|\bfantastic,?\s+vol(?:ume)?\.?\s*2\b/i.freeze
      REFERENCE_ALBUM_MAX_DURATION = 7_200
      AUDIO_FILE_RE = /(?:~\/|\/|\.{1,2}\/)?[^\s"'<>()]+\.(?:wav|mp3|flac|m4a|aac|ogg|opus|mp4|webm)\b/i.freeze
      REFERENCE_GENERATION_RE = /\b(?:make|create|generate|compose|render|produce)\b.*\b(?:like (?:that|this|it)|in (?:that|this) style|same (?:sound|style)|from (?:that|this) reference)\b/i.freeze
      REFERENCE_FOLLOWUP_RE = REFERENCE_GENERATION_RE
      INDUSTRIAL_TECHNO_RE = /\b(?:make|create|generate|compose|render|produce)\b.*\bindustrial[ -]techno\b|\bindustrial[ -]techno\b.*\b(?:track|music|beat|loop|instrumental)\b/i.freeze
      TECHNO_TRACK_RE = /\b(?:make|create|generate|compose|render|produce)\b.*\btechno\b|\btechno\b.*\b(?:track|music|beat|loop|instrumental)\b/i.freeze
      SYNTH_RE = /\b(?:play|generate|create|make|render)\b.*\b(?:sine|square|triangle|saw|white|brown)\b.*\b(?:wave|noise|tone)\b/i.freeze
      # "Play" means the speakers and "make" means a file. A sentence that says
      # both ("make and play") gets the file, which it can then play.
      LIVE_RE = /\b(?:play|live|sound\s*card|speakers?)\b/i.freeze
      FILE_RE = /\b(?:make|render|generate|create|save|write|export)\b/i.freeze
      # "play it", "play that on my sound card": the last thing rendered.
      PLAY_LAST_RE = /\A\s*(?:please\s+)?(?:re)?play\s+(?:it|that|this|the\s+(?:last|file|wav|render|track|beat))\b/i.freeze
      # A sentence addressed to the music: an instrument needs a musical verb, so
      # "open the patch" and "turn the lead into a test" stay chat.
      LIVE_SYNTH_PLAY_RE = /\b(?:play|morph\w*|fade|switch|jam)\b.*\b(?:(?:mini)?moog|model\s*d|prophet|rhodes|juno|synth\w*|pads?|lead|bass(?:line)?|brass|strings|flute|pluck|lo-?fi|chords?|progressions?|something)\b/i.freeze
      LIVE_MUSIC_RE = /\b(?:play|start|resume|put on|queue)\b.*\b(?:liveset|default\s+music|dilla(?:\.rb)?|royksopp(?:\.rb)?|madlib(?:\.rb)?|fly(?:ing)?\s+lotus|flylo|sound\s*card|speakers?)\b/i.freeze
      LIVE_MUSIC_PLAIN_RE = /\b(?:play|start|resume|put on|queue)\b.*\b(?:some\s+|the\s+|your\s+|my\s+)?music\b/i.freeze
      LIVE_AUDIO_STOP_RE = /\b(?:stop|kill|silence|mute|shut\s+off)\b.*\b(?:music|playing|sound|audio|synth\w*|liveset|jam)\b|\b(?:music|playing|sound|audio|synth\w*|liveset)\b.*\b(?:stop|kill|silence|mute|shut\s+off)\b/i.freeze
      LIVE_AUDIO_DIAGNOSTIC_RE = /\b(?:i\s+)?(?:can't|cannot|can\s*not|don't|do\s+not)\s+(?:hear|listen\s+to)\b|\b(?:no|nothing|zero)\s+(?:sound|audio|music)\b|\b(?:it's|it\s+is)\s+silent\b/i.freeze
      LIVE_STYLE_RE = /\b(?:j\s*dilla|dilla|bach|baroque|madlib|flying\s+lotus|flylo|r[öo]yksopp|melody\s+a\.m\.)\b/i.freeze
      LIVE_STYLE_VERB_RE = /\b(?:play|start|resume|switch|change|move|go|use|put\s+on|queue)\b|\b(?:sound\s*card|speakers?)\b/i.freeze
      LIVE_STYLE_QUERY_RE = /\b(?:switch|change|move|go)\b.*\bstyle\b/i.freeze
      LIVE_STYLE_ALONE_RE = /\A\s*(?:j\s*dilla|dilla|bach|baroque|madlib|flying\s+lotus|flylo|r[öo]yksopp|melody\s+a\.m\.)\s*[.!]?\s*\z/i.freeze
      BACKGROUND_MUSIC_RE = /\b(?:play|start|resume|put on|queue)\b.*\b(?:your|some|the|my)?\s*music\b.*\bbackground\b/i.freeze
      LIVE_SYNTH_ALONE_RE = /\A\s*(?:stop|silence|enough)\b|\bstop\s+(?:the\s+)?(?:music|playing|synth\w*|improvi\w*|jam)\b|\b(?:improvi[sz]e|keep\s+playing)\b|\A\s*(?:please\s+)?play(?:\s+(?:some\s+)?music)?\s*[.!]?\s*\z/i.freeze
      POSTPRO_COMMAND_RE = /\b(?:run|use|call|invoke)\s+postpro(?:\.rb)?\b/i.freeze
      POSTPRO_CAPABILITY_RE = /\A\s*(?:can|could|are\s+you\s+able\s+to|do\s+you)\b.*\b(?:use|run|call|invoke)\s+postpro(?:\.rb)?\s*\??\s*\z/i.freeze
      POSTPRO_RE = /\b(?:post-?process|colour\s+grade|color\s+grade|film\s+look|vhs(?:\s+tape)?\s+look|crt(?:\s+broadcast)?\s+look|camcorder(?:\s+glitch)?\s+look|make\s+this\s+(?:cinematic|analog|analogue))\b/i.freeze
      IMAGE_PATH_RE = /(?:["']([^"']+\.(?:jpe?g|png|webp|tiff?))["']|(?:\A|\s)([^\s"']+\.(?:jpe?g|png|webp|tiff?))(?=\z|\s))/i.freeze
      POSTPRO_SUBJECT_RE = /\bpostpro(?:\.rb)?\b.*?\b(?:over|on|in|for|from)\b\s+["']([^"']+)["']/i.freeze
      POSTPRO_SUBJECT_TOKEN_RE = /\bpostpro(?:\.rb)?\b.*?\b(?:over|on|in|for|from)\b\s+(?:these|the|my|new)?\s*(?:photos?|images?|pictures?|files?)?\s*(?:in|at|from|under)?\s*(~?(?:\/|\.\/|\.\.\/)?[^\s"']+\/?)(?=\z|\s)/i.freeze
      POSTPRO_PATH_TOKEN_RE = /\b(?:in|at|from|under)\s+(~?(?:\/|\.\/|\.\.\/)[^\s"']+\/?)(?=\z|\s)/i.freeze
      DESKTOP_RE = /\b(?:my\s+|the\s+)?(?:local\s+)?desktop(?:\s+folder)?\b/i.freeze
      POSTPRO_RANDOM_RE = /\b(?:random|randomly|variations?|versions?)\b/i.freeze
      POSTPRO_EXTREME_RE = /\b(?:extreme|wild|aggressive|rough)\b/i.freeze
      POSTPRO_IMAGE_GLOB_RE = %r{(?:~|/)[^\s"\']*[\*?\[\]{}][^\s"\']*\.(?:jpe?g|png|webp|tiff?)\b}i.freeze

      # A question asking for advice is never a render: "should I quit my stable job to make music full time?"
      # matched AUDIO_RE on 2026-10-22 and started dilla. "could you" and "can you" stay requests.
      ADVICE_RE = /\A\s*(?:should\s+(?:i|we)|am\s+i|is\s+it\s+(?:worth|wise|smart|too\s+late|a\s+good\s+idea)|
                  do\s+you\s+think|would\s+it\s+be|what\s+if\s+i|how\s+do\s+i\s+know)\b/ix.freeze
      # A question about music is discussion: "why did J Dilla use loose timing?" read "use" as a play verb.
      DISCUSSION_RE = /\A\s*(?:why|who|when|did|does|was|were|how\s+(?:did|does|was)|what\s+(?:did|does|was|made))
                       \b.*\?\s*\z/imx.freeze

      def handles?(text)
        return false if text.match?(ADVICE_RE) || text.match?(DISCUSSION_RE)

        LoraIntent.handles?(text) || reference_audio_request?(text) || reference_followup_request?(text) || text.match?(INDUSTRIAL_TECHNO_RE) || text.match?(TECHNO_TRACK_RE) || text.match?(KICK_RE) || text.match?(PLAY_LAST_RE) || text.match?(SYNTH_RE) || text.match?(LIVE_AUDIO_STOP_RE) || live_synth?(text) || POSTPRO_CAPABILITY_RE.match?(text) ||
          text.match?(BACKGROUND_MUSIC_RE) || text.match?(LIVE_AUDIO_DIAGNOSTIC_RE) || text.match?(AUDIO_RE) || postpro_intent?(text) ||
          text.match?(IMAGE_RE) && text.match?(/\b(?:photo|portrait|image|picture)\b/i)
      end

      def dispatch(text, root: MasterPaths.root, bus: nil)
        return LoraIntent.dispatch(text, root:) if LoraIntent.handles?(text)
        if reference_audio_request?(text)
          return analyze_and_generate_reference(text, root:) if reference_generation_request?(text)
          return analyze_reference(text, root:)
        end
        if reference_followup_request?(text) && !text.match?(INDUSTRIAL_TECHNO_RE) && !text.match?(TECHNO_TRACK_RE) && !text.match?(LIVE_STYLE_RE)
          return generate_from_reference(text, root:)
        end
        return generate_kick(text, root:) if text.match?(KICK_RE)
        return generate_industrial_techno(text, root:) if text.match?(INDUSTRIAL_TECHNO_RE) || text.match?(TECHNO_TRACK_RE)
        return postpro_capability if POSTPRO_CAPABILITY_RE.match?(text)
        return play_last(text, root:) if text.match?(PLAY_LAST_RE)
        return generate_tone(text, root:) if text.match?(SYNTH_RE)
        return stop_live_audio(root:, bus:) if text.match?(LIVE_AUDIO_STOP_RE)
        return diagnose_live_audio(root:) if text.match?(LIVE_AUDIO_DIAGNOSTIC_RE)
        return live_synth(text, root:, bus:) if live_synth?(text)
        return play_background_music(text, root:, bus:) if text.match?(BACKGROUND_MUSIC_RE)
        return postprocess(text, root:) if postpro_intent?(text)
        return generate_beat(text, root:) if text.match?(AUDIO_RE)

        generate_cloud_image(text, root:)
      end

      def postpro_intent?(text)
        parsed = NaturalIntent.resolve(text)
        return true if parsed&.intent == :postprocess

        text.match?(POSTPRO_COMMAND_RE) || text.match?(POSTPRO_RE) || text.match?(POSTPRO_IMAGE_GLOB_RE)
      end

      # Io::MediaLanes picks the lane. Replicate first, or no key for any lane,
      # keeps the replicate tool path below exactly as it was (its prompt craft,
      # sidecars and postpro handoff); another live lane answers through the
      # selector; keys present with every lane parked is the selector's typed offline.
      def generate_cloud_image(prompt, root:)
        lane = MediaLanes.first_live(:image)
        return generate_replicate_image(prompt, root:) if lane.nil? ? !MediaLanes.configured?(:image) : lane.provider == "replicate"
        made = MediaLanes.generate(:image, prompt)
        made.ok? ? Result.ok({ output: made.value!.fetch("path"), rendered: made.value!.fetch("path"), media: made.value!.fetch("lane"), path: made.value!.fetch("path") }) : made
      end

      def generate_replicate_image(prompt, root:)
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
          File.expand_path("~/desktop"),
        ].find { |path| File.directory?(path) }
      end

      def downloads_directory
        [
          File.expand_path("~/Downloads"),
          File.expand_path("~/downloads"),
          File.expand_path("~/storage/downloads"),
          "/sdcard/Download",
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
        pattern = /\b(\d+)\s+(?:(?:random|extreme|wild|aggressive|rough|postpro(?:\.rb)?)\s+)*(?:variations?|versions?|images?|photos?)\b/i
        text.match(pattern)&.captures&.first.to_i.clamp(1, 24).tap do |count|
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

      # The browser face carries its own loop of the same music, so a music
      # ask ships a client_action beside the speaker dispatch: a bare toggle,
      # a named artist, or an explicit stop. Empty-handed when no harmony is
      # named — the face keeps whatever artist it was playing.
      FACE_MUSIC_ARTISTS = {
        /\bmadlib\w*\b/i => "madlib",
        /\bfly(?:ing)?\s+lotus\b|\bflylo\b/i => "flying_lotus",
        /\br[öo]yksopp\b|\bmelody\s+a\.m\.\b/i => "royksopp",
        /\b(?:j\s*dilla|dilla)\b/i => "j_dilla",
        /\bbach\b|\bbaroque\b/i => "bach",
      }.freeze

      def face_music_artist(text)
        FACE_MUSIC_ARTISTS.find { |pattern, _artist| text.match?(pattern) }&.last
      end

      def publish_face_music(bus, payload)
        bus&.publish("client_action", { action: "dilla_bg" }.merge(payload))
      end

      # The player a /play started. dilla.rb renders a file and ends; the sound
      # card is MASTER's, so MASTER holds the pid and is the one that stops it.
      def player_pid
        pid = @player_pid
        return unless pid

        Process.kill(0, pid)
        pid
      rescue Errno::ESRCH, Errno::EPERM
        @player_pid = nil
      end

      def stop_live_audio(root: MasterPaths.root, bus: nil)
        Voice::Playback.interrupt!("operator requested audio stop") if defined?(Voice::Playback)
        pid = player_pid
        Process.kill("TERM", pid) if pid
        @player_pid = nil
        publish_face_music(bus, stop: true)
        line = pid ? "stopped the Dilla player (pid #{pid})" : "nothing is playing"
        Result.ok({ output: line, rendered: line, media: :dilla_stop })
      rescue Errno::ESRCH
        Result.ok({ output: "nothing is playing", rendered: "nothing is playing", media: :dilla_stop })
      end

      def diagnose_live_audio(root: MasterPaths.root)
        pid = player_pid
        rendered = if pid
                     "audio0: playing (pid #{pid}); MASTER can verify the player process, but not whether the operating-system output route is physically audible."
                   else
                     "audio0: nothing is playing; the Dilla player is not running."
                   end
        Result.ok({ output: rendered, rendered:, media: :dilla_audio_diagnostic })
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
        [LIVE_MUSIC_RE, LIVE_MUSIC_PLAIN_RE, LIVE_SYNTH_ALONE_RE, LIVE_SYNTH_PLAY_RE, LIVE_STYLE_QUERY_RE, LIVE_STYLE_ALONE_RE].any? { |pattern| text.match?(pattern) } ||
          (text.match?(LIVE_STYLE_RE) && text.match?(LIVE_STYLE_VERB_RE))
      end

      def repeatable?(text)
        text.match?(PLAY_LAST_RE) ||
          text.match?(LIVE_MUSIC_RE) ||
          text.match?(SYNTH_RE) && text.match?(LIVE_RE) && !text.match?(FILE_RE) ||
          live_synth?(text) && text.match?(LIVE_RE)
      end

      def postpro_capability
        line = "postpro0: ready — provide an existing image file or directory path; default selection is the five newest images"
        Result.ok(output: line, rendered: line, media: :postpro_help)
      end

      def reference_audio_request?(text)
        source = text.match(REFERENCE_URL_RE)&.to_s&.sub(/[.,!?;:]+\z/, "") || text.match(AUDIO_FILE_RE)&.to_s
        return false unless source
        return true if text.match?(REFERENCE_AUDIO_RE) || text.match?(REFERENCE_STYLE_RE) || reference_generation_request?(text)
        # A pasted YouTube URL by itself is an audio reference in MASTER's music workflow.
        remainder = text.gsub(REFERENCE_URL_RE, "").gsub(/\b(?:and|or)\b|&/i, "").strip
        remainder.match?(/\A[.,!?;:\s]*\z/) && text.match?(REFERENCE_URL_RE)
      end

      def reference_style_for(text)
        return "general" if text.match?(REFERENCE_GENERAL_RE)
        return "industrial_techno" if text.match?(/\bindustrial[ -]?techno\b/i)
        return "j_dilla" if text.match?(/\bj\s*dilla\b|\bdilla\b|\bslum\s+village\b|\bboom[ -]?bap\b|\bhip[ -]?hop\b|\bfantastic,?\s+vol(?:ume)?\.?\s*2\b/i)
        return "industrial_techno" if text.match?(/\btechno\b/i)

        active_reference_style
      end

      def reference_generation_request?(text)
        text.match?(REFERENCE_URL_RE) && text.match?(REFERENCE_GENERATION_RE)
      end

      def reference_followup_request?(text)
        text.match?(REFERENCE_FOLLOWUP_RE)
      end

      def reference_root
        Contracts::Studio.output_path(kind: :reference_root)
      end

      def reference_profile_path(style = nil)
        return File.join(reference_root, "latest_profile.json") unless %w[j_dilla industrial_techno].include?(style.to_s)

        File.join(reference_root, "profiles", style.to_s, "latest_profile.json")
      end

      def active_reference_style_path
        File.join(reference_root, "active_style.json")
      end

      def active_reference_style
        style = stored_active_style
        return style if %w[j_dilla industrial_techno].include?(style)

        remembered = latest_reference_profile&.fetch("style_key", nil)
        %w[j_dilla industrial_techno].include?(remembered) ? remembered : "general"
      end

      def stored_active_style
        value = JSON.parse(File.read(active_reference_style_path))
        value["style_key"] if value.is_a?(Hash)
      rescue Errno::ENOENT, JSON::ParserError, TypeError
        nil
      end

      def latest_reference_profile(style: nil)
        profile = JSON.parse(File.read(reference_profile_path(style)))
        profile if profile.is_a?(Hash)
      rescue Errno::ENOENT, JSON::ParserError, TypeError
        nil
      end

      def reference_sources(text)
        urls = text.to_s.scan(REFERENCE_URL_RE).map { |url| url.sub(/[.,!?;:]+\z/, "") }.reject(&:empty?).uniq
        return urls unless urls.empty?

        source = text.to_s.match(AUDIO_FILE_RE)&.to_s
        source ? [source] : []
      end

      def analyze_reference(text, root:)
        sources = reference_sources(text)
        return Result.err("dilla reference: provide a YouTube URL or local audio file", category: :validation) if sources.empty?
        return Result.err("dilla reference: analyze at most #{REFERENCE_SOURCE_LIMIT} links per request", category: :validation) if sources.size > REFERENCE_SOURCE_LIMIT

        style = reference_style_for(text)
        outputs = []
        sources.each_with_index do |source, index|
          args = ["reference", source]
          args.concat(["--max-duration", REFERENCE_ALBUM_MAX_DURATION.to_s]) if text.match?(REFERENCE_ALBUM_RE)
          args.concat(["--style", style]) unless style == "general"
          args << "--no-stems" if text.match?(/\bwithout stems\b|\bskip (?:the )?stem separation\b/i)
          result = ScriptDispatch.run(root:, tool: "dilla", arg: args.map { |value| Shellwords.escape(value) }.join(" "))
          return result unless result.ok?

          outputs << "reference #{index + 1}/#{sources.size}: #{result.value!}"
        end
        output = outputs.join("\n")
        Result.ok({ output:, rendered: output, media: :audio_reference_analysis, style:, source_count: sources.size })
      end

      def analyze_and_generate_reference(text, root:)
        analysis = analyze_reference(text, root:)
        return analysis unless analysis.ok?
        generated = if reference_style_for(text) == "industrial_techno"
                      generate_industrial_techno(text, root:)
                    else
                      generate_beat(text, root:)
                    end
        return generated unless generated.ok?
        output = [analysis.value![:rendered], generated.value![:rendered]].compact.join("\n")
        Result.ok(generated.value!.merge(output:, rendered: output, reference_analysis: analysis.value![:rendered]))
      end

      def generate_from_reference(text, root:)
        case active_reference_style
        when "industrial_techno"
          generate_industrial_techno(text, root:)
        else
          generate_beat(text, root:)
        end
      end

      def generate_industrial_techno(text, root:)
        now = Time.now.utc
        output_path = File.join(dilla_renders_dir(at: now), "industrial-techno-#{now.strftime('%Y%m%dT%H%M%SZ')}.wav")
        args = ["industrial-techno", "--out", output_path]
        bpm = text.match(/\b(\d{2,3}(?:\.\d+)?)\s*bpm\b/i)&.captures&.first
        args.concat(["--bpm", bpm]) if bpm
        bars = text.match(/\b(\d{1,2})\s+bars?\b/i)&.captures&.first
        args.concat(["--bars", bars]) if bars
        result = ScriptDispatch.run(root:, tool: "dilla", arg: args.map { |value| Shellwords.escape(value) }.join(" "))
        return result unless result.ok?
        output = result.value!.to_s
        Result.ok({ output:, rendered: output, media: :industrial_techno, path: output_path })
      end

      # STUDIO owns the dated render directory and enforces the output-path policy.
      def dilla_renders_dir(at: Time.now.utc)
        Contracts::Studio.output_path(kind: :dilla_render_directory, at:)
      end

      # Keep every audition distinct, including two commands within the same second.
      def dilla_unique_render_path(prefix, at: Time.now.utc)
        directory = dilla_renders_dir(at:)
        stamp = at.strftime("%Y%m%dT%H%M%SZ")
        candidate = File.join(directory, "#{prefix}-#{stamp}.wav")
        suffix = 0
        while File.exist?(candidate) || File.symlink?(candidate)
          suffix += 1
          candidate = File.join(directory, "#{prefix}-#{stamp}-#{suffix}.wav")
        end
        candidate
      end

      # The bare MASTER audition is the same curated composition as `ruby dilla.rb`.
      # Skip video encoding here; the interactive path needs the canonical audio.
      def render_dilla_showcase(root:, output: nil)
        now = Time.now.utc
        output ||= dilla_unique_render_path("blue-hour", at: now)
        FileUtils.mkdir_p(File.dirname(output))
        argv = ["--showcase", "--no-video", "--out", output]
        result = ScriptDispatch.run(root:, tool: "dilla", arg: argv.map { |value| Shellwords.escape(value) }.join(" "))
        return result unless result.ok?

        Result.ok({ log: result.value!, path: output, progression: "Blue Hour — Dilla Minor Dub Cut",
                    drums: "dilla_shadow_full", groove: "dilla_shadow", kit: "kit_dust", tempo_range: [92, 116] })
      end

      # What dilla.rb can render, read from its own --list rather than from its
      # data file, so MASTER names no progression or drum pattern of its own.
      def dilla_menu(root)
        listing = ScriptDispatch.run(root:, tool: "dilla", arg: "--list")
        return listing unless listing.ok?

        lines = listing.value!.to_s.lines.map(&:chomp)
        progressions = lines.drop_while { |l| !l.start_with?("Progressions:") }.drop(1).take_while { |l| !l.strip.empty? }.filter_map { |l| l[/\A\s+(\d+)\s/, 1] }
        drums = lines.find { |l| l.start_with?("Drum patterns:") }.to_s.delete_prefix("Drum patterns:").split(",").map(&:strip).reject(&:empty?)
        profiles = lines.find { |l| l.start_with?("Groove profiles:") }.to_s.delete_prefix("Groove profiles:").split(",").map(&:strip).reject(&:empty?)
        return Result.err("dilla: --list named no progressions", category: :infrastructure) if progressions.empty?

        Result.ok({ progressions:, drums:, profiles: })
      end

      # A progression and a drum pattern: explicit choices win; a learned J Dilla
      # reference then steers tempo and pocket. Dilla itself owns all menu values.
      def render_dilla(text, root:, output: nil)
        return render_dilla_showcase(root:, output:) if text.to_s.strip.empty?

        menu = dilla_menu(root)
        return menu unless menu.ok?

        choices = menu.value!
        named = text[/\bprogression\s+(\d+)\b/i, 1] || text[/\A\s*(\d+)(?![\d.])/, 1]
        progression = choices[:progressions].include?(named) ? named : choices[:progressions].sample
        # Explicit Dilla requests must not depend on prior reference analysis.
        explicit_dilla = text.match?(/\b(?:j\s*dilla|dilla|boom[ -]?bap|hip[ -]?hop)\b/i)
        named_other_style = text.match?(/\b(?:bach|baroque|flying lotus|flylo|madlib|royksopp|industrial[ -]?techno|techno)\b/i) && !explicit_dilla
        reference = if explicit_dilla
                      dilla_reference_profile
                    elsif !named_other_style && active_reference_style == "j_dilla"
                      dilla_reference_profile
                    end
        dilla_pocket = !named_other_style && (reference || explicit_dilla)
        named_pattern = choices[:drums].find { |id| text.match?(/\b#{Regexp.escape(id)}\b/) }
        dilla_patterns = %w[dilla_shadow_full dilla_broken_full dilla_shadow dilla_broken dusty_laid_back boom_bap]
        density = reference_feature(reference, "onset_density_per_bar") if dilla_pocket
        offbeat = reference_feature(reference, "offbeat_onset_share") if dilla_pocket
        ranked_patterns = []
        ranked_patterns << "dusty_laid_back" if density && density < 7.5
        ranked_patterns << "dilla_broken_full" if offbeat && offbeat > 0.60
        ranked_patterns.concat(dilla_patterns)
        pattern = named_pattern || if dilla_pocket
                                     ranked_patterns.uniq.find { |id| choices[:drums].include?(id) } || choices[:drums].sample
                                   else
                                     choices[:drums].sample
                                   end
        groove = if dilla_pocket
                   preferred = reference&.fetch("groove_profile", nil)
                   [preferred, "dilla_shadow", "behind_the_beat", "late_snare"].compact.find { |name| choices[:profiles].include?(name) }
                 end
        groove_scale = reference_groove_scale(reference) if dilla_pocket
        explicit_bpm = text.match(/\b(\d{2,3}(?:\.\d+)?)\s*bpm\b/i)&.captures&.first
        bpm = explicit_bpm ? explicit_bpm.to_f : (reference&.fetch("target_bpm", nil) || (dilla_pocket ? 92 : nil))
        drum_balance = reference_balance_adjustment(reference, "drums_energy_share") if dilla_pocket
        chord_balance = reference_balance_adjustment(reference, "other_energy_share") if dilla_pocket
        unless output
          output = dilla_unique_render_path("#{progression}-#{pattern}")
        end
        FileUtils.mkdir_p(File.dirname(output))
        argv = ["--progression", progression, "--out", output]
        argv.concat(["--drums", pattern]) if pattern
        argv.concat(["--profile", groove]) if groove
        argv.concat(["--groove", groove_scale.to_s]) unless groove_scale.nil?
        argv.concat(["--bpm", bpm.to_s]) if bpm
        argv.concat(["--drum-balance", drum_balance.to_s]) unless drum_balance.nil?
        argv.concat(["--chord-balance", chord_balance.to_s]) unless chord_balance.nil?
        if dilla_pocket
          argv.concat(["--effect-rig", "dilla_night", "--kit", "kit_dust", "--voice", "rhodes_mark1",
                       "--sonitex", "subtle", "--sonitex-instances", "2", "--vcs", "0.54"])
        end
        result = ScriptDispatch.run(root:, tool: "dilla", arg: argv.map { |v| Shellwords.escape(v) }.join(" "))
        return result unless result.ok?

        Result.ok({ log: result.value!, path: output, progression:, drums: pattern, groove:, groove_scale:, bpm:,
                    drum_balance:, chord_balance:, kit: dilla_pocket ? "kit_dust" : nil })
      end

      def reference_feature(profile, feature)
        features = profile&.fetch("features", nil)
        return unless features.is_a?(Hash)

        value = Float(features.fetch(feature))
        value if value.finite?
      rescue ArgumentError, TypeError, KeyError
        nil
      end

      # Grid spread only modulates Dilla's existing pocket; it never replaces its
      # musical profile. Keep the learned move close to unity and strictly bounded.
      def reference_groove_scale(profile)
        spread = reference_feature(profile, "timing_spread_ms")
        return unless spread

        (1.0 + (spread - 8.0) * 0.012).clamp(0.85, 1.25).round(2)
      end

      # Translate measured relative stem power into small dB moves around
      # Dilla's own mix defaults. Missing or invalid stem data means no override.
      def reference_balance_adjustment(profile, feature)
        features = profile&.fetch("features", nil)
        return unless features.is_a?(Hash)

        share = Float(features.fetch(feature))
        return unless share.finite?

        ((share.clamp(0.0, 1.0) - 0.25) * 8.0).clamp(-2.0, 2.0).round(1)
      rescue ArgumentError, TypeError, KeyError
        nil
      end

      def dilla_reference_profile
        latest_reference_profile(style: "j_dilla")
      end

      # `/play list` names what a render can be asked for; the chords stay in
      # dilla's own --list so MASTER holds no second copy of them.
      def list_dilla(root)
        menu = dilla_menu(root)
        return menu unless menu.ok?

        choices = menu.value!
        line = [
          "progressions #{choices[:progressions].first}..#{choices[:progressions].last} (#{choices[:progressions].size})",
          "drum patterns #{choices[:drums].join(", ")}",
          "groove profiles #{choices[:profiles].join(", ")}",
        ].join("\n")
        Result.ok(output: line, rendered: line, media: :dilla_list)
      end

      def play_live_music(arg, root: MasterPaths.root, bus: nil)
        return list_dilla(root) if arg.to_s.strip.match?(/\A(?:--)?list\z/i)

        rendered = render_dilla(arg.to_s, root:)
        return rendered unless rendered.ok?

        info = rendered.value!
        stop_player
        @player_pid = Master::Music::Synth.play(info[:path])
        line = "playing #{info[:progression]}#{" with #{info[:drums]}" if info[:drums]} (pid #{@player_pid}): #{info[:path]}"
        Result.ok(output: line, rendered: line, media: :dilla_live, style: info[:progression], path: info[:path],
                  drums: info[:drums], kit: info[:kit])
      rescue RuntimeError, ArgumentError => e
        Result.err("#{e.message}: install sox (brew install sox) or ffmpeg, whose ffplay also plays", category: :infrastructure)
      end

      def stop_player
        pid = player_pid
        Process.kill("TERM", pid) if pid
        @player_pid = nil
      rescue Errno::ESRCH
        @player_pid = nil
      end

      def play_background_music(text, root: MasterPaths.root, bus: nil)
        result = play_live_music(text, root:, bus:)
        return result unless result.ok?

        artist = face_music_artist(text)
        publish_face_music(bus, artist ? { artist: } : {})
        result
      end

      def live_synth(text, root: MasterPaths.root, bus: nil)
        result = play_live_music(text, root:, bus:)
        return result unless result.ok?

        artist = face_music_artist(text)
        publish_face_music(bus, artist:) if artist
        result
      end

      # What this surface writes: tones and kicks as master-*.wav, beats as
      # <progression>-<UTC stamp>.wav.
      RENDERED_MEDIA = %w[master-*.wav *-2???????T??????Z.wav].freeze

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

      def generate_beat(text, root:)
        FileUtils.mkdir_p(MEDIA_OUTPUT_DIR)
        output = File.join(MEDIA_OUTPUT_DIR, "dilla-#{Time.now.utc.strftime('%Y%m%dT%H%M%SZ')}.wav")
        rendered = render_dilla(text, root:, output:)
        return rendered unless rendered.ok?

        info = rendered.value!
        Result.ok({ output: info[:log], rendered: info[:log], media: :dilla, path: output, progression: info[:progression], drums: info[:drums] })
      end
    end
  end
end
