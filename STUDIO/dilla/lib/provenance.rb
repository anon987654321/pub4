# frozen_string_literal: true

require "json"
require "digest"
require "time"
require "English"
require_relative "engine_sources"
require_relative "knobs"
require_relative "frozen_state"

# Every rendered file gets a recipe beside it, so any render can be made again.
#
# Before this, none could. RENDER_SEED already pinned the whole engine — patch
# selection, all 31 anoisesrc sites, render_rand, the 26 seeds built out of
# Ruby's per-process String#hash — and that work was thorough. What was missing
# is that nothing ever wrote the seed down. Unset, the engine draws from
# Process.pid and ffmpeg's own RNG, so a render was gone the moment it finished:
# su_tunnel_choir.wav (2026-08-11 03:35) cannot be reproduced, and neither can
# any of the 616 audio files beside it.
#
# So the seed is always chosen now, never left to chance-without-a-record. If
# RENDER_SEED is set, that is used and honoured exactly as before. If it is not,
# one is drawn at random — the render still differs from the last, which is the
# behaviour the engine documents and wants — and then written into a .dilla file
# next to every audio file the run produced.
#
# The consequence worth stating plainly: an unpinned render is now produced
# through the pinned code paths, because ENV["RENDER_SEED"] is set before any of
# them run. render_pinned? is true, so noise comes from seed_for(tag) rather than
# ffmpeg's seed=-1, and render_rand is seeded rather than rand. Two unpinned
# renders still differ from each other exactly as they did. What changes is that
# each one is now a draw that can be replayed instead of one that cannot.
#
# DILLA_NO_PROVENANCE=1 restores the old behaviour completely, seed and all.
module DillaProvenance
  MANIFEST_EXT = ".dilla"
  AUDIO = %w[.wav .mp3 .flac .ogg .m4a .aiff .aif].freeze
  SCHEMA = "dilla.render.v1"

  # Directories whose contents are inputs rather than outputs. Recording a
  # recipe for a sample someone dragged in would be a lie about where it came
  # from, and .cache holds generated copies nothing should be asked to rebuild.
  SKIP = %r{/(\.git|\.cache|node_modules)/}

  class << self
    attr_reader :seed, :started_at

    def disabled? = ENV["DILLA_NO_PROVENANCE"] == "1"

    # Called once, before any command runs.
    def begin!(root: Dir.pwd, argv: ARGV)
      return if disabled?

      @root = root
      @argv = argv.dup
      @started_at = Time.now
      @seed = pin_seed!
      @before = snapshot
      @explicit = @explicit_seed
      at_exit { finish! }
    end

    # A seed exists for every render. An explicitly set RENDER_SEED is left
    # alone — someone comparing two renders has chosen their constant and this
    # must not move it.
    def pin_seed!
      given = ENV["RENDER_SEED"].to_s
      if given.empty?
        @explicit_seed = false
        drawn = Random.new_seed % (2**31)
        ENV["RENDER_SEED"] = drawn.to_s
        drawn
      else
        @explicit_seed = true
        given.to_i
      end
    end

    def finish!
      return if disabled? || @before.nil?
      return if @finished

      @finished = true
      produced.each { |path| write_manifest(path) }
    rescue StandardError => e
      # A render that succeeded must not be reported as failed because its
      # bookkeeping did not.
      warn "provenance: #{e.class}: #{e.message}"
    end

    def produced
      snapshot.reject { |path, mtime| @before[path] == mtime }.keys
    end

    def snapshot
      Dir.glob(File.join(@root, "**", "*{#{AUDIO.join(',')}}"))
         .reject { |p| p.match?(SKIP) }
         .each_with_object({}) { |p, acc| acc[p] = (File.mtime(p).to_f rescue nil) }
    end

    def manifest_for(path)
      {
        "schema" => SCHEMA,
        # The pins belong in the sentence that claims reproduction. Without them
        # it read "Reproduce with: RENDER_SEED=… ruby dilla.rb out.wav" over a
        # take rendered with fifteen knobs set, and RELEASE.mp3's own sidecar is
        # the proof that a confident note over an incomplete command gets
        # believed for months.
        "note" => "Reproduce with: #{reproduce_command}",
        "render_seed" => @seed,
        "seed_was" => @explicit ? "given" : "drawn and recorded",
        "command" => { "argv" => @argv, "cwd" => @root },
        "engine" => engine_identity,
        "environment" => recorded_env,
        # The knobs the OPERATOR set, as opposed to the ones a defaults table
        # filled in. This is the difference between a recipe and a transcript.
        "pinned" => pinned_env,
        # Knobs this run computed for itself. Not inputs; see derived_env.
        "derived" => derived_env,
        # A frozen render read the learned state and wrote none of it back, so
        # the take beside this manifest was made against state that has not
        # moved since. Worth recording: it is the difference between a take that
        # can be compared with another and one that cannot.
        "frozen" => (DillaFrozen.skips if DillaFrozen.on?),
        # What this file was joined from, when it was joined rather than
        # rendered. A compilation gets both blocks: the environment describes
        # the run that produced its parts, `assembly` describes the parts.
        "assembly" => assemblies[path.to_s],
        "artifact" => artifact(path),
        "rendered_at" => @started_at&.utc&.iso8601,
      }.compact
    end

    def reproduce_command
      pins = pinned_env.map { |k, v| "#{k}=#{v}" }
      (["RENDER_SEED=#{@seed}"] + pins + ["ruby dilla.rb"] + @argv).join(" ")
    end

    # What the caller actually typed.
    #
    # `environment` records all 172 knobs the run ended up with, and replaying
    # that is not replaying the run: env_locks.rb distinguishes a value the
    # operator pinned from one a style table soft-filled, and soft fill only
    # wins when nothing set the key first. Feed the whole recorded environment
    # back in and every engine-chosen default arrives as an operator pin, so the
    # tables that would have chosen them are locked out and the replay diverges
    # from the take it claims to reproduce -- most visibly on tracks whose own
    # progression is supposed to overwrite the default.
    #
    # USER_PINNED_ENV is captured in dilla.rb before any require can mutate ENV,
    # which is exactly the set wanted here. Absent (provenance loaded on its own,
    # as the tests do) this records nothing rather than guessing.
    def pinned_env
      return {} unless Object.const_defined?(:USER_PINNED_ENV)

      keys = engine_env_keys
      Object.const_get(:USER_PINNED_ENV).select do |key, value|
        keys.include?(key) && !value.to_s.empty? &&
          !ENV_DENY.include?(key) && !key.match?(ENV_DENY_PATTERN) &&
          !DillaKnobs::ENGINE_WRITTEN.include?(key)
      end
    end

    # The knobs that change what comes out, derived from the engine rather than
    # listed by hand.
    #
    # The first version was a hand-kept allow-list of eleven names. v4 was
    # rendered with fifteen knobs set and the manifest recorded six of them --
    # PAD_VOL, GROOVE_FEEL, KICK_GAIN, ANALOG_CHAIN, SONITEX and RAP_VOCAL all
    # missing -- so the file said "reproduce with" above a command that would
    # not. A provenance record that is silently partial is worse than none,
    # because it is believed.
    #
    # So the set is whatever the engine actually reads: every ENV["X"] and
    # ENV.fetch("X" in dilla.rb and lib/. That cannot go stale against a new
    # knob, which a list maintained beside the code always does.
    #
    # It went stale anyway, against a moved knob rather than a new one. The glob
    # was `lib/*.rb`, one level deep, which was every file lib/ had until the
    # engine was split into lib/engine/ (c94fe8b00). After it, the scan found 126
    # of 610 knobs: PROGRESSION, SONITEX, RAP_VOCAL, ANALOG_CHAIN, PAD_VOL and
    # KICK_GAIN were all missing again — five of the six names in the paragraph
    # above, recorded there as the reason the hand-kept list was abandoned. The
    # manifests written between the split and this fix say "reproduce with" over
    # a command that will not.
    #
    # Recursing fixed that instance and left the cause: this file still had its
    # own opinion about which files the engine is, and so did four other places.
    # It reads DillaSources now, which is the only one. A directory move cannot
    # produce a third occurrence unless it defeats that file too, and that file
    # is what the tests point at.
    #
    # Deliberately not "every variable currently set": this file is written next
    # to audio that gets shared, and the environment holds credentials.
    ENV_READ = /ENV(?:\.fetch)?\[?\(?["']([A-Z][A-Z0-9_]{2,})["']/

    def engine_env_keys
      @engine_env_keys ||=
        DillaSources.all.flat_map { |f| File.read(f).scan(ENV_READ).flatten rescue [] }.uniq.freeze
    end

    # The engine reads HOME and PATH like any program does, and they are not
    # knobs. RENDER_SEED has its own field. The pattern is the safety net the
    # comment above promises: this file sits beside audio that gets shared, and
    # a manifest is a bad place to learn that an API key was in the environment.
    #
    # The toolchain names are here for the same reason and were found the same
    # way: BUNDLE_GEMFILE is read by lib/music_gems.rb, so it is a knob by this
    # module's definition and turned up in `pinned` next to BARS and SONITEX as
    # though someone had chosen it. It says which Gemfile the shell happened to
    # export, which is not part of how a beat was made.
    ENV_DENY = %w[
      HOME PATH PWD OLDPWD SHELL SHLVL TERM TMPDIR USER LOGNAME LANG LC_ALL
      EDITOR VISUAL DISPLAY SSH_AUTH_SOCK RENDER_SEED
      BUNDLE_GEMFILE BUNDLE_PATH BUNDLE_BIN_PATH GEM_HOME GEM_PATH
      RBENV_VERSION RUBYOPT RUBYLIB
      GROK_AGENT
    ].freeze
    ENV_DENY_PATTERN = /KEY|TOKEN|SECRET|PASSWORD|PASSWD|CREDENTIAL|AUTH|COOKIE|SESSION/i

    def recorded_env
      engine_env_keys.each_with_object({}) do |key, acc|
        next if ENV_DENY.include?(key) || key.match?(ENV_DENY_PATTERN)
        # A knob the engine WRITES is an output of this render, not an input to
        # it. DILLA_RENDER_SEED is set by drum_kit.rb from the seed that is
        # already recorded above, so replaying a manifest verbatim fed a result
        # back in as a cause. Recorded separately below, under a name that says
        # what it is.
        next if DillaKnobs::ENGINE_WRITTEN.include?(key)

        value = ENV[key]
        acc[key] = value unless value.nil? || value.empty?
      end
    end

    # What the run computed for itself. Kept because it is useful to see, and
    # kept out of `environment` because replaying it would be wrong.
    def derived_env
      DillaKnobs::ENGINE_WRITTEN.each_with_object({}) do |key, acc|
        value = ENV[key]
        acc[key] = value unless value.nil? || value.empty?
      end
    end

    # The engine root is lib/'s parent, and the pathspecs are relative to it. The
    # first version ran git from lib/ with `-- dilla.rb lib`, which matches
    # nothing from there: the commit came back null and, worse, `status
    # --porcelain` came back empty and was read as "clean". It reported a clean
    # working tree having failed to look at one, while dilla.rb was in fact
    # dirty. An unknown is recorded as null now, never as the good answer.
    def engine_root = File.expand_path("..", __dir__)

    def git(*args)
      out = IO.popen(["git", "-C", engine_root, *args], err: File::NULL, &:read)
      $CHILD_STATUS&.success? ? out.strip : nil
    rescue StandardError
      nil
    end

    def engine_identity
      sha = git("log", "-1", "--format=%H", "--", "dilla.rb", "lib")
      status = git("status", "--porcelain", "--", "dilla.rb", "lib")
      {
        "file" => "dilla.rb",
        "commit" => (sha unless sha.to_s.empty?),
        # A dirty engine means the commit alone will not rebuild this. nil means
        # git could not be asked, which is not the same as clean.
        "working_tree_clean" => status.nil? ? nil : status.empty?,
        "ruby" => RUBY_VERSION,
      }
    end

    # --- assembly ---------------------------------------------------------------
    #
    # A recipe per rendered file was never enough, because the files that matter
    # most are not rendered, they are assembled.
    #
    # RELEASE.mp3 is 44 minutes and its sidecar describes a 160-second render:
    # the same seed, the same command, one sixteenth of the artifact. Working out
    # what was actually in it took envelope fingerprinting of every audio file
    # still on disk against the master, and the answer was four identifiable
    # takes, fifteen minutes that matched nothing, and a 21-minute compilation
    # that was itself an assembly of about ten more. None of that was written
    # down anywhere, and most of the parts no longer exist -- renders are
    # gitignored and the seed rotates, so a part that is gone is gone.
    #
    # Which is why each part's own recipe is INLINED here rather than referenced.
    # A manifest that points at a .dilla file beside a deleted wav records
    # nothing. Inlined, the assembly still says what every part was made from
    # after every part has been swept.
    ASSEMBLY_SCHEMA = "dilla.assembly.v1"

    def assemblies = @assemblies ||= {}

    # parts: the files joined, in order. how: a sentence about the join.
    def record_assembly!(output, parts:, how:)
      return if disabled?

      # Assemblies happen from commands that may never have called begin!.
      @root ||= Dir.pwd
      @argv ||= []
      @started_at ||= Time.now
      offset = 0.0
      described = parts.map do |part|
        seconds = duration_of(part)
        entry = {
          "path" => part.to_s.sub("#{@root}/", ""),
          "starts_at" => offset.round(3),
          "seconds" => seconds&.round(3),
          "bytes" => (File.size(part) if File.file?(part)),
          "sha256" => (Digest::SHA256.file(part).hexdigest if File.file?(part)),
          # The part's own recipe, copied in. See the note above.
          "recipe" => part_recipe(part),
        }.compact
        offset += seconds.to_f
        entry
      end

      assemblies[output.to_s] = {
        "schema" => ASSEMBLY_SCHEMA,
        "how" => how,
        "parts" => described.length,
        "seconds" => offset.round(3),
        "assembled_at" => Time.now.utc.iso8601,
        "from" => described,
      }
      write_manifest(output) if File.file?(output)
      assemblies[output.to_s]
    rescue StandardError => e
      # An assembly that succeeded must not be reported as failed because its
      # bookkeeping did not -- the same rule finish! follows.
      warn "provenance: assembly record failed: #{e.class}: #{e.message}"
      nil
    end

    def part_recipe(part)
      manifest = "#{part}#{MANIFEST_EXT}"
      return unless File.file?(manifest)

      doc = JSON.parse(File.read(manifest))
      {
        "render_seed" => doc["render_seed"],
        "pinned" => doc["pinned"],
        "note" => doc["note"],
        "engine_commit" => doc.dig("engine", "commit"),
      }.compact
    rescue StandardError
      nil
    end

    def duration_of(path)
      return unless File.file?(path)

      out = IO.popen(["ffprobe", "-v", "error", "-show_entries", "format=duration",
                      "-of", "default=nk=1:nw=1", path.to_s], err: File::NULL, &:read)
      value = out.to_s.strip.to_f
      value.positive? ? value : nil
    rescue StandardError
      nil
    end

    def artifact(path)
      {
        "path" => path.sub("#{@root}/", ""),
        "bytes" => File.size(path),
        "sha256" => Digest::SHA256.file(path).hexdigest,
      }
    end

    def write_manifest(path)
      File.write("#{path}#{MANIFEST_EXT}", JSON.pretty_generate(manifest_for(path)) + "\n")
    end

    # `dilla replay <file.dilla>` — prints the command that rebuilds it.
    #
    # From `pinned` when the manifest has one, because that is what the operator
    # typed and letting the engine choose the rest is what the original run did.
    # Manifests written before `pinned` existed only have `environment`, and for
    # those this falls back to it and says so -- an imperfect replay the reader
    # knows is imperfect beats a perfect-looking one that is not.
    def replay_command(manifest_path)
      doc = JSON.parse(File.read(manifest_path))
      pinned = doc["pinned"]
      source = pinned && !pinned.empty? ? pinned : doc["environment"]
      env = source.map { |k, v| "#{k}=#{v}" }
      command = (["RENDER_SEED=#{doc['render_seed']}"] + env + ["ruby dilla.rb"] + doc["command"]["argv"]).join(" ")
      return command if pinned

      "# no `pinned` in this manifest (written before it was recorded); every engine-chosen\n" \
      "# default below arrives as an operator pin, which is not how the take was rendered.\n#{command}"
    end
  end
end
