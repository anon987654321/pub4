# frozen_string_literal: true

require "json"
require "digest"
require "time"
require "English"

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
        "note" => "Reproduce with: RENDER_SEED=#{@seed} ruby dilla.rb #{@argv.join(' ')}",
        "render_seed" => @seed,
        "seed_was" => @explicit ? "given" : "drawn and recorded",
        "command" => { "argv" => @argv, "cwd" => @root },
        "engine" => engine_identity,
        "environment" => recorded_env,
        "artifact" => artifact(path),
        "rendered_at" => @started_at.utc.iso8601,
      }
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
    # a command that will not. Recurse, so the next move down a directory is not
    # a third occurrence.
    #
    # Deliberately not "every variable currently set": this file is written next
    # to audio that gets shared, and the environment holds credentials.
    ENV_READ = /ENV(?:\.fetch)?\[?\(?["']([A-Z][A-Z0-9_]{2,})["']/

    def engine_env_keys
      @engine_env_keys ||= begin
        sources = [File.join(engine_root, "dilla.rb")] + Dir.glob(File.join(engine_root, "lib", "**", "*.rb"))
        sources.flat_map { |f| File.read(f).scan(ENV_READ).flatten rescue [] }.uniq.freeze
      end
    end

    # The engine reads HOME and PATH like any program does, and they are not
    # knobs. RENDER_SEED has its own field. The pattern is the safety net the
    # comment above promises: this file sits beside audio that gets shared, and
    # a manifest is a bad place to learn that an API key was in the environment.
    ENV_DENY = %w[
      HOME PATH PWD OLDPWD SHELL SHLVL TERM TMPDIR USER LOGNAME LANG LC_ALL
      EDITOR VISUAL DISPLAY SSH_AUTH_SOCK RENDER_SEED
    ].freeze
    ENV_DENY_PATTERN = /KEY|TOKEN|SECRET|PASSWORD|PASSWD|CREDENTIAL|AUTH|COOKIE|SESSION/i

    def recorded_env
      engine_env_keys.each_with_object({}) do |key, acc|
        next if ENV_DENY.include?(key) || key.match?(ENV_DENY_PATTERN)

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
    def replay_command(manifest_path)
      doc = JSON.parse(File.read(manifest_path))
      env = doc["environment"].map { |k, v| "#{k}=#{v}" }
      (["RENDER_SEED=#{doc['render_seed']}"] + env + ["ruby dilla.rb"] + doc["command"]["argv"]).join(" ")
    end
  end
end
