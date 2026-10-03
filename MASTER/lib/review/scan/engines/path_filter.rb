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
        # fixing. `scratch` is the same shape — MASTER/tools/dilla/scratch holds a
        # demucs virtualenv, so `/scan ../MASTER/tools/dilla` walked 24,521 files,
        # about 5,000 of them pip's vendored copy of packaging, to reach the 36
        # Ruby files the tool is made of. Skipping both: 793 files in 38s, and
        # the findings are about dilla instead of about torch. Nothing under
        # either segment is git-tracked anywhere in this repo, so nothing under
        # either can be authored or refactored — and /fix descends the same
        # tree, so an autofix pass could rewrite a vendored Python package that
        # the next `pip install` silently reverts.
        #
        # reports/ is generated output. Scanning it meant the top
        # COPY_PASTE_BLOCK findings were JSON manifests from three
        # screenshot-calibration runs, which share keys because they share a
        # schema — and the advice attached to them was "extract a module or
        # template". Nothing in there is authored, so nothing can be refactored.
        #
        # Comments stay above the %w literal: inside it, every word of one is an
        # entry, and a directory named "schema" or "module" would vanish.
        SKIP_PATH_SEGMENTS = %w[
          .git vendor node_modules tmp log coverage .bundle storage cache dist build
          knowledge fixtures var .cache scratch
          site-packages venv .venv venv-demucs __pycache__
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
        # The four generated face bundles are their own constant because
        # lib/operator/self_findings.rb needs the same four and had its own copy of
        # them inside a regex. One fact, one home; the census reads this.
        GENERATED_FACE_BUNDLES = %w[
          web/public/three.face.module.js web/public/face.runtime.js
          web/public/face.modules.bundle.js web/public/face_vision.bundle.js
        ].freeze
        SKIP_RELATIVE_PATHS = (%w[
          .master runtime web/public/assets web/script/three_build web/node_modules web/tmp web/log
        ] + GENERATED_FACE_BUNDLES).flat_map { |path| [path, "MASTER/#{path}"] }.freeze

        # Not authored anywhere: `builds/` is what dartsass compiles the tracked
        # _*.scss into, so every finding in it is a duplicate of one already
        # reported against the source, and fixing the copy is undone by the next
        # `bin/rails css:build`. shared/reference holds the original CodePen
        # sources kept for provenance and shipped by nothing, and lightgallery
        # arrived minified from jsDelivr.
        #
        # Each entry names a path that is tracked or gitignored build output;
        # test_scan_path_filter holds that, because an exemption whose subject is
        # gone excuses whatever next takes its name.
        SKIP_PATH_PREFIXES = %w[
          RAILS/shared/reference
        ].freeze
        # public/assets/ is what Propshaft precompiles into, gitignored in every
        # app, and a finding there is a finding against a digest copy.
        SKIP_PATH_FRAGMENTS = %w[
          public/assets/
          app/assets/builds/
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
        #
        # app/views/pwa/service-worker.js is Workbox's minified bundle, written per
        # app by `npm run build:pwa` (RAILS/tools/build_workbox.mjs): every finding
        # in it is about Workbox, and the next build undoes any fix.
        SKIP_PATH_SUFFIXES = %w[db/schema.rb db/structure.sql app/views/pwa/service-worker.js].freeze

        def skip_path?(path, root: nil)
          segments = relative_segments(path, root)
          return true if SKIP_PATH_SEGMENTS.any? { |segment| segments.include?(segment) }

          rel = relative_path(path, root)
          return true if SKIP_PATH_SUFFIXES.any? { |suffix| rel == suffix || rel.end_with?("/#{suffix}") }
          return true if SKIP_PATH_PREFIXES.any? { |prefix| rel == prefix || rel.start_with?("#{prefix}/") }
          return true if SKIP_PATH_FRAGMENTS.any? { |fragment| rel.include?(fragment) }
          return true if VENDORED_ASSET.match?(rel)

          SKIP_RELATIVE_PATHS.any? { |prefix| under?(rel, prefix) || under?(master_relative(path), prefix) }
        end

        def under?(rel, prefix) = rel == prefix || rel.start_with?("#{prefix}/")

        # A scan rooted inside MASTER — `/scan face` is web/public — sees
        # face.runtime.js as a bare basename that no MASTER-relative entry
        # matches, so the generated bundles and web/public/assets were walked and
        # offered to /fix. Anchoring on MASTER as well makes the list hold from any
        # root beneath it.
        def master_relative(path)
          relative_path(path, Master::ROOT)
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
