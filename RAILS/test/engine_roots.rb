# frozen_string_literal: true

# The checks and these tests share one statement of where brgen's engines live.
# On vm23 this file sits at /home/brgen/test, where the repo-relative path lands on /home/MASTER and the
# whole brgen suite died loading it on 2026-10-22; so the checkout comes from PUB4_ROOT (exported by
# ci-run.ksh), then the repo, then the box's own checkout, the order Shared::Contracts uses.
surfaces = File.join("MASTER", "checks", "support", "brgen_vertical_surfaces.rb")
roots = [ENV["PUB4_ROOT"].to_s.strip, File.expand_path("../..", __dir__), "/home/dev/pub4"].reject(&:empty?)
require File.join(roots.find { |root| File.file?(File.join(root, surfaces)) } || roots.first, surfaces)
