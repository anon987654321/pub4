# frozen_string_literal: true

module Master
  module Review
    module Scan
      # What the scanner refuses to look at. Every entry here is a path nobody
      # authored, so a finding against it is a finding against a generator and
      # a fix to it is reverted by the next build. `bin/gate`'s full mode runs
      # /fix over whatever the scan walked, so this list is also what stops an
      # autofix pass rewriting vendored and rendered output.
      module PathFilter
        module_function

        # `.cache` and `scratch` (2026-08-11): `cache` was listed and `.cache`
        # was not, which bin/gate already warned about in a comment rather than
        # fixing. `scratch` is the same shape — STUDIO/dilla/scratch holds a
        # demucs virtualenv, so `/scan ../STUDIO/dilla` walked 24,521 files,
        # about 5,000 of them pip's vendored copy of packaging, to reach the 36
        # Ruby files the tool is made of. Skipping both: 793 files in 38s, and
        # the findings are about dilla instead of about torch. Nothing under
        # either segment is git-tracked anywhere in this repo, so nothing under
        # either can be authored or refactored — and /fix descends the same
        # tree, so an autofix pass could rewrite a vendored Python package that
        # the next `pip install` silently reverts.
        SKIP_PATH_SEGMENTS = %w[
          .git vendor node_modules tmp log coverage .bundle storage cache dist build
          knowledge fixtures var .cache scratch
          site-packages venv .venv venv-demucs __pycache__
          # reports/ is generated output. Scanning it meant the top
          # COPY_PASTE_BLOCK findings were JSON manifests from three
          # screenshot-calibration runs, which share keys because they share a
          # schema — and the advice attached to them was "extract a module or
          # template". Nothing in here is authored, so nothing in here can be
          # refactored.
          reports
        ].freeze
        # Spelled relative to MASTER, and matched relative to whatever root the
        # scan was given — which are the same thing only when MASTER scans
        # itself. `bin/gate` and every cross-tree run pass the repo root, where
        # these paths arrive as `MASTER/web/public/face.runtime.js` and matched
        # nothing: the generated face runtime, the two bundles and the three
        # build were scanned, reported, and offered to /fix. face.runtime.js
        # opens with "do not edit by hand" and is rewritten by
        # assets:build_face_runtime, so a fix there survives until the next
        # build and then vanishes — the same loop the db/schema.rb note below
        # describes. Matching the MASTER-prefixed form too makes the list mean
        # the same thing from both roots.
        SKIP_RELATIVE_PATHS = %w[
          .master runtime web/public/assets web/script/three_build web/node_modules web/tmp web/log
          web/public/three.face.module.js web/public/face.runtime.js
          web/public/face.modules.bundle.js web/public/face_vision.bundle.js
        ].flat_map { |path| [path, "MASTER/#{path}"] }.freeze

        # Not authored anywhere: `builds/` is what dartsass compiles the tracked
        # _*.scss into, so every finding in it is a duplicate of one already
        # reported against the source, and fixing the copy is undone by the next
        # `bin/rails css:build`. shared/reference holds the original CodePen
        # sources kept for provenance and shipped by nothing, and lightgallery
        # arrived minified from jsDelivr.
        SKIP_PATH_PREFIXES = %w[
          RAILS/shared/reference
          STUDIO/dilla/archive
        ].freeze
        # `reference/` is the same claim SKIP_PATH_PREFIXES makes about
        # RAILS/shared/reference, at the path brgen actually uses.
        # visualizers_2d_reference.js opens with "Reference only. Not loaded,
        # not imported, not compiled into anything" and already carries an
        # opt-out marker for a second linter that read it as live.
        SKIP_PATH_FRAGMENTS = %w[
          app/assets/builds/
          app/javascript/reference/
        ].freeze

        # Third-party assets checked in under public/ rather than vendor/, so the
        # `vendor` segment never matched them. lightgallery arrived minified from
        # jsDelivr and swiper is a `.min.css` bundle; both were reported for
        # touch-target size and missing prefers-reduced-motion, neither of which
        # anyone here can fix without forking the library. `.min.*` is the general
        # form of the same claim: minified means generated elsewhere.
        VENDORED_ASSET = %r{
          /public/(?:lightgallery|swiper[\w.-]*|photoswipe[\w.-]*)\.(?:css|js)\z
          | \.min\.(?:css|js)\z
        }x
        # Rails writes these; ActiveRecord::SchemaDumper does not emit a
        # frozen_string_literal magic comment, so FROZEN_STRING_LITERAL
        # (autofix: true) added one and the next `db:migrate` stripped it again.
        # That loop produced a spurious dirty db/schema.rb for whoever migrated
        # next, on a shared git index where a stray modification gets swept into
        # someone else's commit. Matched by suffix rather than prefix because
        # they sit under RAILS/<app>/, and the scan root is the repo.
        SKIP_PATH_SUFFIXES = %w[db/schema.rb db/structure.sql].freeze

        def skip_path?(path, root: nil)
          segments = relative_segments(path, root)
          return true if SKIP_PATH_SEGMENTS.any? { |segment| segments.include?(segment) }

          rel = relative_path(path, root)
          return true if SKIP_PATH_SUFFIXES.any? { |suffix| rel == suffix || rel.end_with?("/#{suffix}") }
          return true if SKIP_PATH_PREFIXES.any? { |prefix| rel == prefix || rel.start_with?("#{prefix}/") }
          return true if SKIP_PATH_FRAGMENTS.any? { |fragment| rel.include?(fragment) }
          return true if VENDORED_ASSET.match?(rel)

          SKIP_RELATIVE_PATHS.any? { |prefix| rel == prefix || rel.start_with?("#{prefix}/") }
        end

        def relative_segments(path, root)
          relative_path(path, root).split(File::SEPARATOR)
        end

        def relative_path(path, root)
          return path.to_s unless root

          expanded = File.expand_path(path)
          base = File.expand_path(root)
          return path.to_s unless expanded == base || expanded.start_with?("#{base}#{File::SEPARATOR}")

          expanded.delete_prefix(base).delete_prefix(File::SEPARATOR)
        end
      end
    end
  end
end
