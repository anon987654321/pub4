# frozen_string_literal: true

require_relative "../../../../OPENBSD/lib/gate_result"

module Deploy
  # PWA-100 and BRGEN-115. Three manifests, and nothing checked that what they
  # declare exists or that what they call the app matches what the page does.
  #
  # The icon check is the reason this is a gate rather than a test, and it is
  # also the trap it exists to encode. An icon in a manifest is a path, not a
  # file, and it resolves from two places: the app's own public/ and the shared
  # engine's, which shared/lib/shared/engine.rb:133 mounts with its own
  # ActionDispatch::Static. Looking in the app's public/ alone reports brgen and
  # bsdports as declaring five icons and shipping two — which is wrong, and is
  # exactly what a hand check found before reading the engine. Amber keeping its
  # own copies is the anomaly, not the other two lacking them.
  #
  # So: resolve every declared icon against both, and fail only when it is in
  # neither. That is the claim worth holding, and it is one nobody can make by
  # listing a directory.
  class PwaInstallable
    # Three levels, not four: gates/lib/source -> gates/lib -> gates -> RAILS.
    # Four lands on the repo root and every path silently misses by one segment.
    ROOT = File.expand_path("../../..", __dir__)
    APPS = %w[brgen amber bsdports].freeze

    # Chrome installs on one 192 and one 512 with purpose "any". Maskable and
    # monochrome are polish; these two are the requirement.
    REQUIRED_SIZES = %w[192x192 512x512].freeze
    REQUIRED_KEYS = %w[name short_name start_url display icons].freeze

    def self.run = new.run

    def run
      @result = GateResult.new
      APPS.each { |app| check_app(app) }
      check_brgen_brand
      @result
    end

    private

    def check_app(app)
      manifest = File.join(ROOT, app, "app/views/pwa/manifest.json.erb")
      unless File.file?(manifest)
        @result.fail("pwa_installable: #{app} has no manifest at #{rel(manifest)}")
        return
      end

      source = File.read(manifest)
      check_keys(app, source)
      check_icons(app, source)
      check_service_worker(app)
    end

    def check_keys(app, source)
      REQUIRED_KEYS.each do |key|
        @result.checked!
        next if source.include?(%("#{key}":))

        @result.fail("pwa_installable: #{app} manifest declares no #{key} — not installable")
      end
    end

    # Every src, resolved against both public roots. The sizes check reads the
    # declared purpose because a manifest of nothing but maskable icons installs
    # nowhere.
    def check_icons(app, source)
      icons = parse_icons(source)
      @result.checked!
      if icons.empty?
        @result.fail("pwa_installable: #{app} manifest lists no icons")
        return
      end

      icons.each do |icon|
        @result.checked!
        next if resolves?(app, icon[:src])

        @result.fail("pwa_installable: #{app} declares #{icon[:src]}, which is in neither " \
                     "#{app}/public nor shared/public")
      end
      check_required_sizes(app, icons)
    end

    # One entry at a time, and an absent purpose is "any".
    #
    # Both halves of that were learned the hard way on the first run. A single
    # regex reading src, sizes and purpose across the whole array pairs entry
    # one's src with entry three's purpose the moment an entry omits the key —
    # and bsdports omits it on exactly the two icons that make it installable,
    # so the gate reported the one app it should have cleared. The spec says an
    # icon with no purpose is "any", which is why omitting it is correct and why
    # a checker that requires it is measuring its own assumption.
    def parse_icons(source)
      block = source[/"icons":\s*\[(.*?)\]/m, 1].to_s
      block.scan(/\{(.*?)\}/m).flatten.filter_map do |entry|
        src = entry[/"src":\s*"([^"]+)"/, 1]
        next unless src

        { src:, sizes: entry[/"sizes":\s*"([^"]+)"/, 1].to_s,
          purpose: entry[/"purpose":\s*"([^"]+)"/, 1] || "any" }
      end
    end

    def check_required_sizes(app, icons)
      any = icons.select { |icon| icon[:purpose] == "any" }
      REQUIRED_SIZES.each do |size|
        @result.checked!
        next if any.any? { |icon| icon[:sizes] == size }

        @result.fail("pwa_installable: #{app} declares no #{size} icon with purpose any — " \
                     "maskable and monochrome do not satisfy the install prompt")
      end
    end

    def check_service_worker(app)
      @result.checked!
      worker = File.join(ROOT, app, "app/views/pwa/service-worker.js")
      return if File.file?(worker)

      @result.fail("pwa_installable: #{app} has no service worker at #{rel(worker)}")
    end

    # BRGEN-115. brgen is the only city-tenanted app of the three, so it is the
    # only one whose manifest must not name a city: the same page is served as
    # Bergen and as Oslo, and a manifest saying Bergen on oshlo.no is visible at
    # install time. amber and bsdports are single-brand and their literals are
    # correct.
    def check_brgen_brand
      @result.checked!
      source = File.read(File.join(ROOT, "brgen/app/views/pwa/manifest.json.erb"))
      unless source.include?("city_name")
        @result.fail("pwa_installable: brgen manifest does not derive its name from city_name — " \
                     "an installed app on oshlo.no would be called Bergen")
        return
      end

      literal = source[/"name":\s*"([A-Z][a-z]+)"/, 1]
      return unless literal

      @result.fail("pwa_installable: brgen manifest hardcodes the name #{literal.inspect}; " \
                   "the city is resolved per host")
    end

    def resolves?(app, src)
      path = src.sub(%r{\A/}, "")
      File.file?(File.join(ROOT, app, "public", path)) ||
        File.file?(File.join(ROOT, "shared", "public", path))
    end

    def rel(path) = path.sub("#{ROOT}/", "")
  end
end
