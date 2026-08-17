# frozen_string_literal: true

require "net/http"
require "uri"
require_relative "../../../../OPENBSD/lib/deploy_inventory"
require_relative "../../../../OPENBSD/lib/gate_result"
require_relative "../../../tools/crawl_support"

module Deploy
  # Public surfaces must not serve Faker filler.
  #
  # This gate exists because the failure it catches was invisible to every other
  # one. On 2026-08-12 brgen.no's sitemap listed 1376 posts and 1088 of them were
  # Latin slugs — /posts/quis-autem-eveniet-sunt-tenetur — while release,
  # production, layout_suite and the whole rendered_suite passed. Every gate in
  # the tree was reading source, and the defect was entirely in rows. A visitor
  # saw it in one scroll; nothing we ran could.
  #
  # Two halves, because the debt has two halves. The source half stops the
  # seeders reintroducing Latin (db/seeds.rb already switched to
  # Brgen::PlausibleContent and says why). The live half is the only thing that
  # can see rows the seeders wrote before that, and it goes through the sitemap
  # because that is the surface a search engine indexes — the exact place filler
  # does the most damage.
  class ContentHonestyGate
    ROOT = File.expand_path("../../../..", __dir__)
    RAILS = File.join(ROOT, "RAILS")

    # Faker::Lorem's own wordlist. Deliberately not "lorem"/"ipsum" alone: that
    # pair appears in almost no generated sentence, which is why eyeballing for
    # "lorem ipsum" had missed a thousand rows.
    MARKERS = %w[
      dolor voluptat eveniet iusto aliquid tenetur suscipit
      eligendi consequatur repellendus necessitatibus quisquam
    ].freeze

    # Seeders that write user-visible post copy. Faker is fine in them for names,
    # cities and prices; it is not fine for a title or a body.
    SEED_SOURCES = [
      "brgen/db/seeds.rb",
      "brgen/lib/brgen/per_city_seeder.rb"
    ].freeze

    FORBIDDEN_SEED_CALL = /(?:title|content|body):\s*Faker::Lorem/

    def self.run
      new.run
    end

    def run
      @result = GateResult.new
      seed_source_check
      live_sitemap_check
      @result
    end

    private

    def seed_source_check
      SEED_SOURCES.each do |rel|
        path = File.join(RAILS, rel)
        unless File.file?(path)
          @result.fail("content_honesty: missing #{rel}")
          next
        end

        File.read(path).each_line.with_index do |line, i|
          next unless line.match?(FORBIDDEN_SEED_CALL)

          @result.fail("content_honesty: #{rel}:#{i + 1} seeds a post from Faker::Lorem — " \
                       "use Brgen::PlausibleContent")
        end
      end
      @result.checked!(SEED_SOURCES.size)
    end

    def live_sitemap_check
      inv = Inventory.new(root: ROOT).apps.find { |a| a.name == "brgen" }
      return @result.inconclusive!("content_honesty: brgen not in inventory — sitemap not probed") unless inv
      unless CrawlSupport.port_open?("127.0.0.1", inv.port)
        return @result.inconclusive!("content_honesty: brgen port closed — sitemap not probed")
      end

      res = fetch("http://127.0.0.1:#{inv.port}/sitemap.xml", host: "brgen.no")
      code = res.code.to_i
      return @result.fail("content_honesty: sitemap HTTP #{code}") unless code == 200

      locs = res.body.to_s.scan(%r{<loc>([^<]+)</loc>}).flatten
      return @result.inconclusive!("content_honesty: sitemap listed no URLs") if locs.empty?

      latin = locs.select { |u| latin_slug?(u) }
      if latin.empty?
        @result.checked!(locs.size)
        return
      end

      # Named, not just counted. A bare number reads as a ratchet to lower;
      # the URLs are what someone has to go and fix.
      @result.fail("content_honesty: #{latin.size} of #{locs.size} sitemap URLs are Faker filler — " \
                   "run `rails brgen:latin:rewrite APPLY=1`. First: #{latin.first(3).join(" ")}")
      @result.checked!(locs.size)
    rescue StandardError => e
      @result.fail("content_honesty live: #{e.class}: #{e.message}")
    end

    def latin_slug?(url)
      slug = url.split("/").last.to_s.downcase
      slug.split("-").any? { |w| MARKERS.any? { |m| w.start_with?(m) } }
    end

    def fetch(url, host: nil)
      uri = URI(url)
      Net::HTTP.start(uri.host, uri.port, open_timeout: 8, read_timeout: 20) do |http|
        req = Net::HTTP::Get.new(uri.request_uri)
        req["Host"] = host if host
        http.request(req)
      end
    end
  end
end
