#!/usr/bin/env ruby
# frozen_string_literal: true

# Rendered frames in, graded catalogue entries out.
#
#   ruby STUDIO/lora/_toolkit/install_seed_media.rb ~/Downloads/seed_render
#   ruby STUDIO/lora/_toolkit/install_seed_media.rb <dir> --dry-run
#
# This is the half of the pipeline that runs on the Mac. The GPU half happens on
# Colab against seed_media.yml; this takes what comes back, puts each frame
# through postpro at the preset its entry asks for, files it where the app will
# look, and writes the catalogue row.
#
# Why a script rather than a note in a README: the seeds resolve an image by
# looking up a key in config/demo_media/<name>.yml, so getting a picture into an
# app means agreeing on a filename, a directory and a YAML row all at once. Done
# by hand across sixty-one keys and three apps, some of them will disagree, and a
# key that disagrees does not fail — Shared::DemoMedia falls through to picsum
# and the app looks seeded. A wrong photograph is visible; a silent fallback to
# stock is not.
#
# Input is a flat directory of <key>.png or <key>.jpg. Anything whose stem is not
# a key in seed_media.yml is reported and skipped rather than guessed at.

require "rbconfig"
require "yaml"
require "fileutils"
require "json"
require "optparse"

ROOT = File.expand_path("../../..", __dir__)
SPEC = File.join(ROOT, "STUDIO/lora/seed_media.yml")
POSTPRO = File.join(ROOT, "STUDIO/postpro/postpro.rb")

# Which app owns a key, and where that app keeps its catalogue. brgen's is the
# city file the seeders already read; amber's is default.yml, which the shared
# Catalog now looks for before falling back to a file named for a city amber is
# not in.
DESTINATIONS = {
  /\Aamber-/ => { app: "amber", catalog: "config/demo_media/default.yml" },
  /\Abergen-/ => { app: "brgen", catalog: "config/demo_media/bergen.yml" },
}.freeze

options = { dry_run: false }
OptionParser.new do |o|
  o.banner = "usage: install_seed_media.rb <render-dir> [--dry-run]"
  o.on("--dry-run", "Report what would be installed and change nothing") { options[:dry_run] = true }
end.parse!

render_dir = ARGV.shift
abort "usage: install_seed_media.rb <render-dir> [--dry-run]" unless render_dir
abort "no such directory: #{render_dir}" unless File.directory?(render_dir)

spec = YAML.safe_load_file(SPEC)

# key => preset. The three populations carry their postpro preset differently —
# dating and amber declare one for the whole group, a scene may override the
# meta default — so the lookup is built once here rather than branched on at
# every use.
presets = {}
spec.dig("dating", "profiles").each_key { |k| presets[k] = spec["dating"]["postpro"] }
spec.dig("amber", "garments").each_key { |k| presets[k] = spec["amber"]["postpro"] }
spec["scenes"].each { |k, v| presets[k] = v["postpro"] || spec["meta"]["postpro"] }

frames = Dir.glob(File.join(render_dir, "*.{png,jpg,jpeg,webp}")).sort
abort "no images in #{render_dir}" if frames.empty?

known, unknown = frames.partition { |f| presets.key?(File.basename(f, ".*")) }
unless unknown.empty?
  warn "skipping #{unknown.size} file(s) whose name is not a key in seed_media.yml:"
  unknown.each { |f| warn "  #{File.basename(f)}" }
end
abort "nothing to install" if known.empty?

installed = Hash.new { |h, k| h[k] = {} }

known.each do |frame|
  key = File.basename(frame, ".*")
  dest = DESTINATIONS.find { |pattern, _| key.match?(pattern) }&.last
  next warn("no destination app for #{key}") unless dest

  app_root = File.join(ROOT, "RAILS", dest[:app])
  catalog_path = File.join(app_root, dest[:catalog])
  media_dir = File.join(File.dirname(catalog_path), "images")
  out = File.join(media_dir, "#{key}.jpg")
  preset = presets.fetch(key)

  if options[:dry_run]
    puts format("  %-32s -> %s [%s]", key, out.sub("#{ROOT}/", ""), preset)
    installed[catalog_path][key] = true
    next
  end

  FileUtils.mkdir_p(media_dir)
  # --input/--output, the same invocation Shared::PostproProcessor uses, because
  # that one is known to work headlessly. Passing the file positionally drops
  # postpro into its interactive picker, which in a script means it hangs or
  # exits having done nothing -- and the frame it was handed is still there
  # afterwards, ungraded and indistinguishable from a graded one.
  ok = system(RbConfig.ruby, POSTPRO,
              "--input", frame, "--output", out, "--preset", preset,
              out: File::NULL, err: File::NULL)
  ok &&= File.exist?(out) && File.size?(out).to_i.positive?

  # A failed grade keeps the ungraded frame rather than nothing, because a
  # missing file falls through to picsum and looks seeded. Reported either way.
  unless ok
    FileUtils.cp(frame, out)
    warn "postpro failed for #{key} (#{preset}) — kept the ungraded frame"
  end

  installed[catalog_path][key] = true
  puts format("  %-32s -> %s [%s]%s", key, out.sub("#{ROOT}/", ""), preset, ok ? "" : " UNGRADED")
end

installed.each do |catalog_path, keys|
  existing = File.file?(catalog_path) ? YAML.safe_load_file(catalog_path) : {}
  existing["images"] ||= {}

  keys.each_key do |key|
    # A relative `file:` rather than a URL. Catalog#file_path resolves it against
    # the catalogue's own directory, so the app carries its own photographs and
    # a seed run needs no network — which is the difference between seeding on
    # the VPS and seeding on the VPS successfully.
    existing["images"][key] = { "file" => "images/#{key}.jpg" }
  end

  next puts("  would write #{keys.size} row(s) to #{catalog_path.sub("#{ROOT}/", '')}") if options[:dry_run]

  FileUtils.mkdir_p(File.dirname(catalog_path))
  File.write(catalog_path, existing.to_yaml)
  puts "wrote #{keys.size} row(s) -> #{catalog_path.sub("#{ROOT}/", '')}"
end

missing = presets.keys - known.map { |f| File.basename(f, ".*") }
puts "\nstill unrendered: #{missing.size} of #{presets.size}"
missing.sort.each { |k| puts "  #{k}" } unless missing.empty?
