# frozen_string_literal: true

# Where a source-reading contract test finds its source.
#
# ROOT, read_brgen and read_source were private to deploy_backlog_test.rb.
# Splitting the infinite-scroll assertions out of that file needed all three,
# and copying them would have made two answers to "where is the tree" that can
# drift — which is the exact failure ROOT's own comment records from 2026-07-10,
# when a stale /home/<app>/pub4-rails/RAILS had every assertion silently checking
# month-old file contents instead of failing.
module SourceReader
    ROOT = ENV.fetch("PUB4_RAILS_ROOT") do
      app = ENV.fetch("PUB4_CI_APP", "brgen")
      candidates = [
        # Canonical checkout first: per-app "pub4-rails" copies are leftovers from
        # older deploy schemes and can go stale relative to the real monorepo
        # without anything noticing (confirmed 2026-07-10: a stale
        # /home/<app>/pub4-rails/RAILS caused every DeployBacklogTest assertion to
        # silently check month-old file contents instead of failing loudly).
        "/home/dev/pub4/RAILS",
        "/home/#{app}/pub4-rails/RAILS",
        File.expand_path("../../..", __dir__)
      ]
      candidates.find { |path| File.readable?(File.join(path, "shared", "app")) } ||
        candidates.find { |path| File.directory?(File.join(path, "shared")) } ||
        candidates.last
    end.freeze

  # The five verticals moved to mountable engines (engines/<v>/app/...), so a path
  # like app/models/tv/channel.rb now lives at engines/tv/app/models/tv/channel.rb.
  # Resolve the host path first, then the engine location, then a flat basename
  # match for assets that moved without a namespace dir. See brgen/ENGINES.md.
  def read_brgen(relative)
    read_source(File.join(ROOT, "brgen", relative))
  end

  # Resolve a ROOT-based source path, falling back to the mountable engines the
  # five verticals moved into (engines/<v>/app/...), then a flat basename match
  # for assets moved without a namespace dir. Migrations stayed in the host and
  # resolve directly. See brgen/ENGINES.md.
  def read_source(abs)
    # brgen's routes now span the host plus every vertical engine — read them as one
    # so "is this route wired" assertions find engine-owned routes too.
    if abs.end_with?("brgen/config/routes.rb") && File.exist?(abs)
      brgen_dir = File.dirname(File.dirname(abs)) # .../brgen (abs is .../brgen/config/routes.rb)
      engine_routes = Dir.glob(File.join(brgen_dir, "engines", "*", "config", "routes.rb")).sort.map { |f| File.read(f) }
      return ([ File.read(abs) ] + engine_routes).join("\n")
    end
    return File.read(abs) if File.exist?(abs)
    rel = abs.sub(%r{\A#{Regexp.escape(File.join(ROOT, "brgen"))}/}, "")
    moved = Dir.glob(File.join(ROOT, "brgen", "engines", "*", rel)).first
    return File.read(moved) if moved
    flat = Dir.glob(File.join(ROOT, "brgen", "engines", "*", "app", "**", File.basename(abs))).first
    return File.read(flat) if flat
    File.read(abs)
  end
end
