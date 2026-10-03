# frozen_string_literal: true

# Where a source-reading contract test finds its source.
#
# On the box the suite runs from /home/brgen/app, where the RAILS tree is not
# the parent directory, so ROOT is found rather than assumed. A stale
# /home/<app>/pub4-rails/RAILS once had every assertion silently checking
# month-old file contents instead of failing.
module SourceReader
    ROOT = ENV.fetch("PUB4_RAILS_ROOT") do
      app = ENV.fetch("PUB4_CI_APP", "brgen")
      candidates = [
        # Canonical checkout first: per-app "pub4-rails" copies are leftovers from
        # older deploy schemes and can go stale relative to the real monorepo
        # without anything noticing (confirmed 2026-07-10: a stale
        # /home/<app>/pub4-rails/RAILS read month-old file contents).
        "/home/dev/pub4/RAILS",
        "/home/#{app}/pub4-rails/RAILS",
        # This file is RAILS/brgen/test/source_reader.rb, so RAILS is two levels
        # up, not three. At three it resolved to the repo root, where no `shared`
        # exists, both `find` guards missed and the chain fell through to the
        # wrong path — 39 errors in brgen's suite on every checkout that is not
        # /home/dev/pub4, which is why the box never saw it.
        File.expand_path("../..", __dir__)
      ]
      candidates.find { |path| File.readable?(File.join(path, "shared", "app")) } ||
        candidates.find { |path| File.directory?(File.join(path, "shared")) } ||
        candidates.last
    end.freeze

  # The five verticals moved to mountable engines (engines/<v>/app/...), so a path
  # like app/models/tv/channel.rb now lives at engines/tv/app/models/tv/channel.rb.
  # Resolve the host path first, then the engine location, then a flat basename
  # match for assets that moved without a namespace dir. See brgen/README.md.
  def read_brgen(relative)
    read_source(File.join(ROOT, "brgen", relative))
  end

  # Resolve a ROOT-based source path, falling back to the mountable engines the
  # five verticals moved into (engines/<v>/app/...), then a flat basename match
  # for assets moved without a namespace dir. Migrations stayed in the host and
  # resolve directly. See brgen/README.md.
  def read_source(abs)
    # brgen's routes now span the host plus every vertical engine — read them as one
    # so "is this route wired" assertions find engine-owned routes too.
    if abs.end_with?("brgen/config/routes.rb") && File.exist?(abs)
      brgen_dir = File.dirname(File.dirname(abs)) # .../brgen (abs is .../brgen/config/routes.rb)
      engine_routes = Dir.glob(File.join(brgen_dir, "engines", "*", "config", "routes.rb")).sort.map { |f| File.read(f) }
      return ([ File.read(abs) ] + engine_routes).join("\n")
    end
    return with_model_concerns(abs) if File.exist?(abs)
    rel = abs.sub(%r{\A#{Regexp.escape(File.join(ROOT, "brgen"))}/}, "")
    moved = Dir.glob(File.join(ROOT, "brgen", "engines", "*", rel)).first
    return with_model_concerns(moved) if moved
    flat = Dir.glob(File.join(ROOT, "brgen", "engines", "*", "app", "**", File.basename(abs))).first
    return File.read(flat) if flat
    File.read(abs)
  end

  # A model is its file plus the concerns in the directory named after it —
  # app/models/conversation.rb and app/models/conversation/*.rb are one class.
  # Reading only the first file would fail a "state machine is wired" assertion
  # the day the state machine moved into Order::Lifecycle, over a spelling.
  def with_model_concerns(path)
    parts = [ File.read(path) ]
    if path.match?(%r{/app/models/.+\.rb\z})
      parts.concat(Dir.glob(File.join(path.delete_suffix(".rb"), "*.rb")).sort.map { |f| File.read(f) })
    end
    parts.join("\n")
  end
end
