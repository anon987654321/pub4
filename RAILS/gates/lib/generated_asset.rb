# frozen_string_literal: true

require_relative "../../../OPENBSD/lib/gate_result"
require_relative "../../../OPENBSD/lib/deploy_inventory"

module Deploy
  class GeneratedAssetGate
    ROOT = File.expand_path("../../..", __dir__)
    RAILS_ROOT = File.join(ROOT, "RAILS")
    # Stylesheets only. app/javascript/**/*.{js,ts} used to be watched here and
    # compared against application.css — but every app serves its JS through
    # importmap, unbundled, so no JS file has application.css as its build
    # artifact and no JS edit can make it stale. Touching a Stimulus controller
    # reported three apps' CSS as needing a rebuild that would change nothing.
    # (The one JS artifact that IS generated, the service worker, has its own
    # check at the bottom of stale?.)
    WATCHED = [
      "app/assets/stylesheets/application.scss",
      "app/assets/stylesheets/**/*.scss",
    ].freeze

    # An app's application.css is compiled from its own stylesheets *and* the
    # shared engine's, which is where the design tokens live — so watching only
    # the app tree let a shared change pass as fresh.
    #
    # It did. amber and bsdports shipped builds that predated
    # shared/.../_tokens.scss gaining --text-title and --text-display: 10 KB and
    # 4 KB of missing CSS respectively, with this gate green over both. Rebuilding
    # them was a no-op for the app trees and a visible change to the pages.
    SHARED_WATCHED = [
      "app/assets/stylesheets/**/*.scss",
    ].freeze

    def self.run
      new.run
    end

    def run
      result = GateResult.new
      inventory = Inventory.new(root: ROOT)
      inventory.apps.each do |app|
        app_dir = File.join(RAILS_ROOT, app.name)
        next unless File.directory?(app_dir)

        stale?(app_dir, result, app.name)
      end
      result
    end

    private

    def source_files(app_dir)
      shared_dir = File.join(RAILS_ROOT, "shared")
      patterns = WATCHED.map { |pattern| File.join(app_dir, pattern) } +
                 SHARED_WATCHED.map { |pattern| File.join(shared_dir, pattern) }
      patterns.flat_map { |pattern| Dir.glob(pattern) }
        .uniq.select { |path| File.file?(path) }
    end

    # Absolute paths with uncommitted changes, or nil when git cannot answer
    # (no repo, no git binary) — in which case the mtime check stands alone
    # rather than silently passing everything.
    def dirty_paths
      return @dirty_paths if defined?(@dirty_paths)

      out = IO.popen(["git", "-C", ROOT, "status", "--porcelain", "-z", "--", "RAILS"], err: File::NULL, &:read)
      @dirty_paths =
        if $?&.success?
          out.split("\0").filter_map { |entry|
            rel = entry[3..]
            File.join(ROOT, rel) if rel && !rel.empty?
          }.to_set
        end
    rescue SystemCallError
      @dirty_paths = nil
    end

    def stale?(app_dir, result, app_name)
      build = File.join(app_dir, "app", "assets", "builds", "application.css")
      sources = source_files(app_dir)
      return if sources.empty?

      unless File.file?(build)
        result.fail("#{app_name}: missing compiled app/assets/builds/application.css")
        return
      end

      build_mtime = File.mtime(build)
      dirty = dirty_paths
      sources.each do |source|
        next if File.mtime(source) <= build_mtime
        # mtime alone is not evidence. `git checkout`/`pull` rewrites every file
        # in one pass, so which of two files lands a millisecond later is write
        # order, not an edit — this reported brgen's _channels.scss (1.3ms) and
        # _nav_swiper.scss (3.7ms) as newer than a build that in fact contained
        # both files' selectors verbatim. A source only counts as stale if it is
        # actually modified in the working tree while the build is not: that is
        # the real failure (edit the SCSS, forget to rebuild). With a clean tree
        # the committed build is by construction the one built from the committed
        # sources, whatever the checkout stamped on them.
        next if dirty && !(dirty.include?(source) && !dirty.include?(build))

        rel = source.sub("#{app_dir}/", "").sub("#{RAILS_ROOT}/", "")
        result.fail("#{app_name}: stale asset build — #{rel} newer than application.css")
      end

      # tools/build_workbox.mjs writes app/views/pwa/service-worker.js — it is
      # served through a route, not from public/. This compared public/, which no
      # app has, so both File.file? guards were false and the whole check was
      # unreachable: shared/pwa/service_worker.js could change and no app's
      # bundle was ever reported stale.
      #
      # Making it reachable then made it wrong for brgen, which no longer builds
      # its service worker at all. Workbox froze ~89 fingerprinted asset URLs in
      # a precache manifest; every deploy re-digests those assets, so `install`
      # started failing with bad-precaching-response and the PWA broke on
      # playlist.brgen.no. brgen replaced the bundle with a hand-rolled worker
      # that precaches only /offline. Telling that app to "run npm run build:pwa"
      # is telling it to reintroduce the outage — and the freshness comparison is
      # meaningless for a file no generator writes.
      #
      # So: check each app against the source it actually has. amber and bsdports
      # still ship the Workbox bundle and are still worth a staleness check;
      # brgen gets the opposite check, that the bundle has not crept back.
      sw_source = File.join(RAILS_ROOT, "shared", "pwa", "service_worker.js")
      sw_build = File.join(app_dir, "app", "views", "pwa", "service-worker.js")
      return unless File.file?(sw_source)

      unless File.file?(sw_build)
        result.fail("#{app_name}: missing app/views/pwa/service-worker.js")
        return
      end

      unless File.read(sw_build).include?("workbox:core")
        result.warn("#{app_name}: service-worker.js is hand-rolled, not built — npm run build:pwa " \
                    "would overwrite it with the Workbox precache bundle it deliberately replaced")
        return
      end

      return unless File.mtime(sw_source) > File.mtime(sw_build)

      result.fail("#{app_name}: stale service-worker.js relative to shared/pwa/service_worker.js " \
                  "— run npm run build:pwa")
    end
  end
end
