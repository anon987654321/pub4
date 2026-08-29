# frozen_string_literal: true

require "json"
require "digest"
require_relative "knobs"

# The inputs a render names, and whether they are still there.
#
# A recipe can name a sample that is not on this machine. RELEASE.mp3's sidecar
# names EXTERNAL_KIT=03-soulful-vintage, which is not in the repository at all --
# it lives in a git clone under ~/.cache that nothing records the identity of --
# and SAMPLE_LOOP as an absolute path into samples/, where 46 of the files are
# untracked. Neither fact is discoverable from the manifest, and a render that
# cannot find a named input does not stop: it falls back, substitutes, and
# produces a perfectly good beat that is not the one the recipe describes.
#
# Two halves, and they answer different questions:
#
#   check_inputs!  did THIS run get what it asked for? Runs at startup, before
#                  a note is rendered, and refuses rather than substitutes.
#   verify         is the crate itself intact? Compares the recorded hashes
#                  against what is on disk, so a sample that was replaced,
#                  re-encoded or truncated is visible.
#
# The manifest is written by hand (`dilla assets record`) rather than on every
# render, because a manifest that updates itself records whatever happened
# instead of what was supposed to happen, and would have nothing to say the day
# a sample changes underneath a take.
module DillaAssets
  SCHEMA = "dilla.assets.v1"

  class << self
    def root = File.expand_path("..", __dir__)
    def manifest_path = File.join(root, "data", "assets.json")

    def manifest
      return { "assets" => {} } unless File.file?(manifest_path)

      JSON.parse(File.read(manifest_path))
    rescue JSON::ParserError => e
      warn "assets: #{manifest_path} is not readable JSON (#{e.message}); treating the crate as unrecorded"
      { "assets" => {} }
    end

    # Everything a recipe can name and a render can quietly do without.
    #
    # Derived from the engine where it can be: the sample-loop rack knows its
    # own paths, and lib/knobs.rb knows which knobs are read as file paths. The
    # drum one-shots are the floor every kit falls back to, so they are named
    # here -- if those are gone, every render is wrong and nothing says so.
    def tracked_paths
      paths = []
      if defined?(TRACK_SAMPLE_LOOPS_BUILTIN)
        paths += TRACK_SAMPLE_LOOPS_BUILTIN.values.filter_map { |entry| entry[:path] }
      end
      paths += Dir[File.join(root, "samples", "drums", "*.wav")]
      paths.select { |path| File.file?(path) }.uniq.sort
    end

    def fingerprint(path)
      {
        "bytes" => File.size(path),
        "sha256" => Digest::SHA256.file(path).hexdigest,
      }
    end

    def record!
      assets = tracked_paths.to_h { |path| [relative(path), fingerprint(path)] }
      payload = {
        "schema" => SCHEMA,
        "note" => "The inputs a recipe can name. `dilla assets` checks them; a mismatch means a take " \
                  "rendered from this crate cannot be rendered from it again.",
        "external_kit_cache" => external_kit_identity,
        "assets" => assets,
      }
      FileUtils.mkdir_p(File.dirname(manifest_path))
      File.write(manifest_path, "#{JSON.pretty_generate(payload)}\n")
      payload
    end

    # missing: recorded and not on disk. changed: on disk and different.
    # unrecorded: on disk, tracked, and never written down.
    def verify
      recorded = manifest["assets"] || {}
      missing = []
      changed = []
      recorded.each do |name, want|
        path = File.join(root, name)
        next missing << name unless File.file?(path)

        got = fingerprint(path)
        changed << "#{name} (#{want['bytes']} bytes → #{got['bytes']})" if got["sha256"] != want["sha256"]
      end
      unrecorded = tracked_paths.map { |p| relative(p) } - recorded.keys
      { missing:, changed:, unrecorded:, recorded: recorded.length }
    end

    # The external drum kits are a shallow git clone outside the repository, so
    # the only honest identity for them is that clone's commit. Absent, renders
    # fall back to the synthesized kit -- which sounds different, and said so
    # nowhere.
    def external_kit_cache = File.expand_path("~/.cache/dilla-samples/free-drum-samples")

    def external_kit_identity
      return { "present" => false } unless Dir.exist?(external_kit_cache)

      head = `git -C #{external_kit_cache.inspect} rev-parse HEAD 2>/dev/null`.strip
      kits = Dir[File.join(external_kit_cache, "drum-samples", "*")].map { |d| File.basename(d) }.sort
      { "present" => true, "commit" => (head unless head.empty?), "kits" => kits }
    end

    # What this run asked for, checked before it renders a note.
    #
    # Returns a list of sentences. Empty means every named input resolved.
    def missing_inputs(env = ENV)
      problems = []

      DillaKnobs.all.each do |name, knob|
        next unless knob.type == :path

        value = env[name].to_s
        next if value.empty? || DillaKnobs::TRUTHY.include?(value.downcase) || DillaKnobs::FALSY.include?(value.downcase)
        # Only values that are actually spelled as a file. A knob read as a path
        # at one site can still be given a slug -- SAMPLE_LOOP takes both.
        next unless value.include?("/") || value.match?(/\.(wav|mp3|flac|ogg|m4a|aiff?)\z/i)
        next if File.exist?(value)

        problems << "#{name}=#{value} names a file that is not here"
      end

      kit = env["EXTERNAL_KIT"].to_s
      unless kit.empty?
        # A kit the engine builds from oneshots it already ships is never in the
        # download cache, and looking for it there refuses a render that would
        # have been correct. external_kit_resolvable? answers for both sources,
        # beside the installer whose branches it mirrors, so a third source is
        # one edit rather than two.
        unless external_kit_resolvable?(kit)
          problems << "EXTERNAL_KIT=#{kit} does not resolve — not in " \
                      "#{relative_home(external_kit_cache)}, and not a builtin kit whose " \
                      "oneshots are here; the render would fall back to the synthesized " \
                      "kit, which is a different sound"
        end
      end

      problems
    end

    private

    def relative(path) = path.sub("#{root}/", "")
    def relative_home(path) = path.sub(Dir.home, "~")
  end
end
