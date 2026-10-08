# frozen_string_literal: true

require "json"
require "yaml"
require "minitest/autorun"

class PwaDesignContractTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)
  SHARED_ROOT = File.join(ROOT, "__shared")
  APPS = %w[amber brgen bsdports].freeze

  # All current apps use the shared Workbox worker. This remains an explicit
  # empty escape hatch: an app that genuinely needs a different worker must name
  # the exception here rather than weakening the common contract.
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
  def test_shared_worker_enforces_network_first_offline_and_retryable_writes
    worker = read(SHARED_ROOT, "pwa/service_worker.js")

    assert_includes worker, 'new NetworkFirst'
    assert_includes worker, "networkTimeoutSeconds: 4"
    assert_includes worker, 'statuses: [200]'
    assert_includes worker, 'caches.match(request)'
    assert_includes worker, 'caches.match("/")'
    assert_includes worker, 'caches.match(OFFLINE_URL)'

    assert_includes worker, 'new BackgroundSyncPlugin(FORM_QUEUE'
    assert_includes worker, 'self.addEventListener("periodicsync"'
    assert_includes worker, 'self.registration.showNotification'
    assert_includes worker, 'clients.openWindow(o)'
  end

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

  def test_offline_snapshot_navigation_is_same_origin_only
    source = read(SHARED_ROOT, "frontend/offline_page_controller.js")
    assert_includes source, "safeUrl(value)"
    assert_includes source, "url.origin === window.location.origin"
    assert_includes source, 'if (!raw) return "#"'
  end

  def test_pwa_runtime_test_is_wired_to_the_root_package
    package = JSON.parse(File.read(File.join(ROOT, "package.json")))

    assert_equal "node --test test/pwa_offline_store.test.mjs",
                 package.fetch("scripts").fetch("test:pwa:runtime")
  end

  def test_offline_replay_queue_is_bounded_and_same_origin
    source = read(SHARED_ROOT, "frontend/pwa_offline_store.js")
    assert_includes source, "MAX_QUEUE_SIZE = 100"
    assert_includes source, "queue.slice(-MAX_QUEUE_SIZE)"
    assert_includes source, "sameOriginUrl(entry.url)"
    assert_includes source, "return null"
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

  # A manifest may be static JSON or an ERB template. Static manifests are the
  # preferred form when the app has no per-request values; dynamic manifests keep
  # ERB only where the host or locale genuinely changes the document.
  ERB_EXPRESSION = /<%=.*?%>/m
  # `<% case vertical %>` — control flow. The document's shape then depends on
  # which branch runs, so there is nothing static to parse.
  ERB_CONTROL_FLOW = /<%[^=#]/

  def test_all_manifests_are_installable
    each_app do |app, root|
      raw = manifest_source(root)
      # Dynamic manifests are checked from their source shape; static JSON is
      # parsed directly. The helper chooses the representation the app ships.
      if raw.match?(ERB_CONTROL_FLOW)
        assert_includes raw, '"start_url"'
        assert_includes raw, '"scope"'
        assert_includes raw, "standalone"
        assert_match(/"theme_color":\s*"#[0-9a-fA-F]{6}"/, raw)
        assert_match(/"background_color":\s*"#[0-9a-fA-F]{6}"/, raw)
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
      assert_equal 1, layout.scan(/stylesheet_link_tag/).length,
                   "#{app}: layout must expose exactly one app stylesheet entrypoint"
      assert_match(/stylesheet_link_tag (?:["'](?:application|app)["']|:app)/, layout)
      assert_match(/<main(?:\s|>)/, layout)
      assert_primary_nav_labelled(app, root, layout)
    end
  end

  def test_store_apps_publish_both_platform_association_endpoints
    each_app do |app, root|
      routes = read(root, "config/routes.rb")
      assert_match(%r{\.well-known/assetlinks\.json}, routes)
      assert_match(%r{\.well-known/apple-app-site-association}, routes)
      assert_includes routes, "rails/pwa#assetlinks"
      assert_includes routes, "rails/pwa#apple_app_site_association"
    end
  end

  def test_pwa_chrome_is_safe_area_and_standalone_aware
    tokens = read(SHARED_ROOT, "app/assets/stylesheets/_dialect_tokens.scss")
    chrome = read(SHARED_ROOT, "app/assets/stylesheets/_layout_chrome.scss")
    shell = read(SHARED_ROOT, "app/assets/stylesheets/_shell.scss")
    standalone = read(SHARED_ROOT, "frontend/pwa_standalone_controller.js")
    prompt = read(SHARED_ROOT, "app/views/shared/_install_prompt.html.erb")

    %w[top right bottom left].each do |side|
      assert_includes tokens, "env(safe-area-inset-#{side}, 0px)"
    end
    assert_includes chrome, "--nav-swiper-h"
    assert_includes chrome, "var(--safe-top)"
    assert_includes shell, "var(--safe-top)"
    assert_includes shell, "var(--safe-bottom)"

    assert_includes standalone, "(display-mode: standalone)"
    assert_includes standalone, "navigator.standalone"
    assert_includes standalone, "pub4:pwa-display"

    assert_includes prompt, 'role="region"'
    assert_includes prompt, "aria-label="
    assert_includes prompt, "install-prompt-secondary"
  end

  def test_shared_typography_uses_optical_and_rhythm_controls
    typography = read(SHARED_ROOT, "app/assets/stylesheets/_typography.scss")

    %w[
      font-feature-settings
      font-kerning
      font-optical-sizing
      font-synthesis
      font-variant-numeric
      text-wrap
    ].each do |property|
      assert_includes typography, property
    end
    assert_includes typography, "hyphens: auto"
    assert_includes typography, "hanging-punctuation:"
  end

  private

  # The invariant is that the primary navigation landmark has an accessible
  # name. `aria-label="Primary navigation"` was the literal proxy for it, and
  # localising the layouts removed the literal while keeping the landmark — so
  # the check failed on three layouts that had all got more correct. Assert the
  # landmark is named through a key that resolves to real copy; the three apps
  # do not agree on the wording (bsdports says "Home"), and never had to.
# The layout plus the partials it renders, not the layout alone.
#
# The landmark itself is what matters, and which file holds it is not
# something this invariant should have an opinion about: brgen's <nav> moved
# into layouts/_sidebar.html.erb on 2026-08-26 when the layout was split for
# length, and this went red on rendered markup that was byte-identical
# before and after. Third assertion in this suite to break that way in one
# pass, which is why it now globs rather than names a file.
def assert_primary_nav_labelled(app, root, layout)
  haystack = layout + Dir.glob(File.join(root, "app/views/{layouts,shared}/_*.erb"))
                         .map { |partial| File.read(partial) }.join
  match = haystack.match(/<nav\b[^>]*aria-label="<%=\s*t\(\s*["']([a-z0-9_.]+)["']/m)
    refute_nil match, "#{app}: no <nav> landmark with a translated aria-label"

    locale = YAML.safe_load_file(File.join(root, "config", "locales", "en.yml")).fetch("en")
    value = match[1].split(".").reduce(locale) { |node, segment| node&.fetch(segment, nil) }
    refute_nil value, "#{app}: nav aria-label uses #{match[1]}, which en.yml does not define"
    refute_empty value.to_s.strip, "#{app}: nav aria-label #{match[1]} is blank"
  end

  def manifest_source(root)
    erb = File.join(root, "app/views/pwa/manifest.json.erb")
    json = File.join(root, "app/views/pwa/manifest.json")
    File.file?(erb) ? File.read(erb) : File.read(json)
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
