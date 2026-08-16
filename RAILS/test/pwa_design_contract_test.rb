# frozen_string_literal: true

require "json"
require "yaml"
require "minitest/autorun"

class PwaDesignContractTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)
  SHARED_ROOT = File.join(ROOT, "shared")
  APPS = %w[amber brgen bsdports].freeze

  # Empty as of 2026-08-14, and kept rather than deleted because the exemption is
  # the thing worth being able to say.
  #
  # brgen was hand-rolled because the Workbox build froze ~89 fingerprinted asset
  # URLs in its precache manifest, every deploy re-digested them, `install` failed
  # with bad-precaching-response, and the PWA broke on playlist.brgen.no.
  # Precaching content-addressed bundles is the wrong tool — but the tool was the
  # glob, not Workbox: build_workbox now ignores assets/**, so the manifest holds
  # only stable URLs and brgen is back on the shared worker with the offline form
  # queue and periodic sync its escape had cost it.
  #
  # If an app needs to leave again, put it here rather than weakening the checks
  # every worker owes regardless of how it is built.
  HAND_ROLLED_WORKERS = [].freeze

  def test_all_apps_ship_a_service_worker_meeting_the_cache_contract
    each_app do |app, root|
      worker = read(root, "app/views/pwa/service-worker.js")
      assert_includes worker, "__CACHE_VERSION__", "#{app}: deploys cannot rotate cache buckets"
      assert_includes worker, "notificationclick", "#{app}: web push notifications open nothing"
      assert_match(/addEventListener\(\s*["']fetch["']/, worker, "#{app}: no fetch handler, so no offline story")
      assert_operator worker.bytesize, :>, 1_000

      if HAND_ROLLED_WORKERS.include?(app)
        assert_includes worker, "offline", "#{app}: hand-rolled worker with no offline fallback"
      else
        assert_includes worker, "Workbox 7.4.1 generated for #{app}"
        assert_includes worker, "offline-forms"
      end
    end
  end

  # The bug that sent brgen away, asserted rather than remembered. A digested URL
  # in a precache manifest is pinned at build time and 404s at the next deploy.
  def test_no_worker_precaches_a_fingerprinted_asset
    each_app do |app, root|
      worker = read(root, "app/views/pwa/service-worker.js")
      pinned = worker.scan(%r{/assets/[^"']*-[0-9a-f]{8,}\.(?:js|css)}).uniq

      assert_empty pinned, "#{app}: precache pins #{pinned.size} digested URL(s); " \
                           "they 404 on the next deploy and fail install"
    end
  end

  # A worker that will not install is a PWA that does not exist, and the failure
  # is silent: registration rejects in the browser and the page renders fine.
  #
  # `render js:` goes through verify_same_origin_request, so without
  # skip_forgery_protection the response is 422 — which is what amber and
  # bsdports answered while brgen, holding the only fixed copy of the same
  # controller, answered 200. app_duplication_test could not see it, because it
  # compares files byte-for-byte and three copies stop being identical the
  # moment one is fixed.
  #
  # Asserted on the shared concern rather than in each app, since that is now the
  # only place the behaviour exists — and asserted per app that they reach it, or
  # the concern could be correct and unused.
  def test_every_app_serves_its_service_worker_through_the_shared_hardening
    concern = read(SHARED_ROOT, "app/controllers/concerns/shared/pwa_serving.rb")
    assert_includes concern, "skip_forgery_protection",
                    "render js: answers 422 without it, so no worker installs"
    assert_includes concern, 'response.headers["Service-Worker-Allowed"] = "/"',
                    "a worker without this controls only its own directory"
    assert_match(/def allow_browser\(\*\)/, concern,
                 "the install fetch does not carry the user agent the modern-browser gate reads")

    each_app do |app, root|
      controller = read(root, "app/controllers/rails/pwa_controller.rb")
      assert_includes controller, "include Shared::PwaServing", "#{app}: serves its own PWA files"
      assert_includes controller, "def pwa_app_name", "#{app}: offline page has no name to show"
      assert_includes controller, "def pwa_storage_key", "#{app}: offline page has no storage key"
    end
  end

  def test_all_apps_register_service_worker_via_pub4_hotwire
    hotwire = read(SHARED_ROOT, "frontend/hotwire.js")
    assert_match(/serviceWorker\.register/, hotwire)
    assert_includes hotwire, "/service-worker"

    each_app do |_app, root|
      routes = read(root, "config/routes.rb")
      javascript = read(root, "app/javascript/application.js", optional: true)
      assert_match(/get ["']offline["']/, routes)
      assert_match(/get ["']service-worker["']/, routes)
      assert_includes javascript, "pub4/hotwire"
    end
  end

  # `<%= raw t("pwa.x").to_json %>` — an interpolated JSON value. Substituting a
  # string literal leaves a document with the same shape, which is what the
  # installability assertions below are about.
  ERB_EXPRESSION = /<%=.*?%>/m
  # `<% case vertical %>` — control flow. The document's shape then depends on
  # which branch runs, so there is nothing static to parse.
  ERB_CONTROL_FLOW = /<%[^=#]/

  def test_all_manifests_are_installable
    each_app do |app, root|
      raw = read(root, "app/views/pwa/manifest.json.erb")
      # This used to switch on `app == "brgen"`, on the grounds that brgen's
      # manifest was the only ERB one. Localising the PWA shortcut labels made
      # every manifest ERB, and amber's then reached JSON.parse and raised.
      # Switch on what the file actually contains instead: an app growing or
      # losing a `case` no longer has to be remembered here.
      if raw.match?(ERB_CONTROL_FLOW)
        assert_includes raw, '"start_url"'
        assert_includes raw, '"scope"'
        assert_includes raw, "standalone"
        assert_includes raw, "#000000"
        assert_includes raw, "when \"playlist\"" if app == "brgen"
        refute_includes raw, "//dating."
        refute_includes raw, "brgen_ai_url"
        next
      end

      manifest = JSON.parse(raw.gsub(ERB_EXPRESSION, '"erb"'))
      assert_equal "/", manifest.fetch("start_url")
      assert_equal "/", manifest.fetch("scope")
      assert_includes %w[standalone fullscreen minimal-ui], manifest.fetch("display")
      assert_operator manifest.fetch("icons").size, :>=, 2
      assert manifest.fetch("theme_color").start_with?("#")
      assert manifest.fetch("background_color").start_with?("#")
    end
  end

  def test_all_layouts_apply_shared_visual_and_accessibility_baseline
    each_app do |app, root|
      layout = read(root, "app/views/layouts/application.html.erb")
      assert_includes layout, "viewport-fit=cover"
      assert_includes layout, 'rel: "manifest"'
      assert_match(/stylesheet_link_tag (?:["'](?:application|app)["']|:app)/, layout)
      assert_match(/<main(?:\s|>)/, layout)
      assert_primary_nav_labelled(app, root, layout)
    end
  end

  private

  # The invariant is that the primary navigation landmark has an accessible
  # name. `aria-label="Primary navigation"` was the literal proxy for it, and
  # localising the layouts removed the literal while keeping the landmark — so
  # the check failed on three layouts that had all got more correct. Assert the
  # landmark is named through a key that resolves to real copy; the three apps
  # do not agree on the wording (bsdports says "Home"), and never had to.
  def assert_primary_nav_labelled(app, root, layout)
    match = layout.match(/<nav\b[^>]*aria-label="<%=\s*t\(\s*["']([a-z0-9_.]+)["']/m)
    refute_nil match, "#{app}: no <nav> landmark with a translated aria-label"

    locale = YAML.safe_load_file(File.join(root, "config", "locales", "en.yml")).fetch("en")
    value = match[1].split(".").reduce(locale) { |node, segment| node&.fetch(segment, nil) }
    refute_nil value, "#{app}: nav aria-label uses #{match[1]}, which en.yml does not define"
    refute_empty value.to_s.strip, "#{app}: nav aria-label #{match[1]} is blank"
  end

  def each_app
    APPS.each { |app| yield app, File.join(ROOT, app) }
  end

  def read(root, relative, optional: false)
    File.read(File.join(root, relative))
  rescue Errno::ENOENT
    return "" if optional
    raise
  end
end
