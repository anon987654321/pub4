# frozen_string_literal: true

require "net/http"
require_relative "../../../OPENBSD/lib/deploy_inventory"
require_relative "../../../OPENBSD/lib/gate_result"
require_relative "../../tools/crawl_support"

module Deploy
  class HumanWalkthroughGate
    ROOT = File.expand_path("../../..", __dir__)
    RAILS_ROOT = File.join(ROOT, "RAILS")

    # Labels may appear as English literals *or* i18n keys (default_locale :nb).
    APP_FILES = {
      "amber" => {
        layout: "app/views/layouts/application.html.erb",
        home: "app/views/home/index.html.erb",
        nav_partials: ["app/views/shared/_sidebar_nav.html.erb"],
        nav: [
          [/Sign\s*in|t\(["']nav\.sign_in["']\)|t\(["']auth\.sign_in["']\)/i, "Sign in"],
          [/Sign\s*up|t\(["']nav\.sign_up["']\)|t\(["']auth\.create_account["']\)/i, "Sign up"],
        ],
      },
      "brgen" => {
        layout: "app/views/layouts/application.html.erb",
        home: "app/views/home/index.html.erb",
        nav_partials: [
          "app/views/shared/_ai_nav_link.html.erb",
          "app/views/shared/_tab_bar.html.erb",
          "app/views/layouts/application.html.erb",
        ],
        nav: [
          [/Home|t\(["']nav\.home["']\)/i, "Home"],
          [/Explore|t\(["']nav\.explore["']\)/i, "Explore"],
          [/Search|t\(["']nav\.search["']\)/i, "Search"],
          [/Sign\s*in|t\(["']nav\.sign_in["']\)|t\(["']auth\.sign_in["']\)/i, "Sign in"],
        ],
        # Mobile tab aria: either English literal or t("nav.*")
        mobile_tabs: [
          /aria:\s*\{[^}]*\blabel:\s*["']Home["']|t\(["']nav\.home["']\)/i,
          /aria:\s*\{[^}]*\blabel:\s*["']Explore[^"']*["']|t\(["']nav\.explore["']\)|t\(["']nav\.communities["']\)/i,
          /aria:\s*\{[^}]*\blabel:\s*["']Messages["']|t\(["']nav\.messages["']\)/i,
          /aria:\s*\{[^}]*\blabel:\s*["']Nearby["']|t\(["']nav\.nearby["']\)/i,
          /AI\s*assistant|t\(["']nav\.ai_assistant["']\)/i,
        ],
      },
      "bsdports" => {
        layout: "app/views/layouts/application.html.erb",
        home: "app/views/ports/index.html.erb",
        nav: [
          [/Ports|t\(["']nav\.ports["']\)/i, "Ports"],
          [/Categories|t\(["']nav\.categories["']\)/i, "Categories"],
          [/Maintainers|t\(["']nav\.maintainers["']\)/i, "Maintainers"],
          [/Sign\s*in|t\(["']nav\.sign_in["']\)|t\(["']auth\.sign_in["']\)/i, "Sign in"],
        ],
      },
    }.freeze

    def self.run
      new.run
    end

    def run
      result = GateResult.new
      inventory = Inventory.new(root: ROOT)
      inventory.apps.each do |app|
        source_checks(result, app)
        live_checks(result, app)
      end
      result
    end

    private

    def read_app_file(app, relative)
      path = File.join(RAILS_ROOT, app, relative)
      File.file?(path) ? File.read(path) : ""
    end

    def source_checks(result, app)
      files = APP_FILES.fetch(app.name)
      layout = read_app_file(app.name, files.fetch(:layout))
      home = read_app_file(app.name, files.fetch(:home))
      nav_source = ([layout, home] + files.fetch(:nav_partials, []).map { |path| read_app_file(app.name, path) }).join("\n")

      result.fail("#{app.name}: layout needs skip link to main content") unless layout.include?('href="#main-content"')
      result.fail("#{app.name}: layout needs main-content landmark") unless layout.include?('id="main-content"')
      result.fail("#{app.name}: home needs data-visitor-orientation marker") unless home.include?("data-visitor-orientation")

      files.fetch(:nav).each do |pattern, label|
        result.fail("#{app.name}: primary visitor nav missing #{label}") unless nav_source.match?(pattern)
      end
      result.checked!(3 + files.fetch(:nav).length)

      if app.name == "brgen"
        result.fail("brgen: sidebar search must submit to global_search_path") unless layout.include?("global_search_path")
        Array(files[:mobile_tabs]).each_with_index do |pat, i|
          result.fail("brgen: mobile tab missing aria/i18n marker ##{i + 1}") unless nav_source.match?(pat)
        end
        result.checked!(1 + Array(files[:mobile_tabs]).size)
      end
    end

    def nokogiri_available?
      return @nokogiri_available if defined?(@nokogiri_available)

      require "nokogiri"
      @nokogiri_available = true
    rescue LoadError
      @nokogiri_available = false
    end

    def live_checks(result, app)
      return result.inconclusive!("#{app.name}: live walkthrough not run; port #{app.port} closed") unless CrawlSupport.port_open?("127.0.0.1", app.port)

      response = CrawlSupport.fetch("http://127.0.0.1:#{app.port}/")
      unless response.code.to_i.between?(200, 399)
        result.fail("#{app.name}: visitor reached HTTP #{response.code} at /")
        return
      end

      html = response.body.to_s
      %w[Exception Routing\ Error].each do |bad|
        result.fail("#{app.name}: visitor saw #{bad.tr('\\', '')}") if html.include?(bad.tr("\\", ""))
      end
      result.checked!(3)

      unless nokogiri_available?
        result.warn("#{app.name}: live HTML structure checks skipped (nokogiri unavailable; source checks still ran)")
        return
      end

      doc = Nokogiri::HTML5(html)
      result.fail("#{app.name}: rendered page missing title") if doc.at("title").to_s.strip.empty?
      result.fail("#{app.name}: rendered page missing main landmark") unless doc.at("main") || html.match?(/id=["']main-content["']|id=["']face["']/)
      result.fail("#{app.name}: rendered page missing primary navigation") unless doc.at("nav") || html.match?(/tab-bar|sidebar/)
      result.fail("#{app.name}: rendered page missing visible heading") unless doc.at("h1, h2")
      result.fail("#{app.name}: rendered page has too few navigable links") if doc.css("a[href]").size < 3

      doc.css('input[type="search"]').each do |input|
        next if input.ancestors("form").any?

        label = input["aria-label"] || input["placeholder"] || "unlabelled search"
        result.fail("#{app.name}: search input is not inside a form (#{label})")
      end
      result.checked!(5 + doc.css('input[type="search"]').size)
    end
  end
end
