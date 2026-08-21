# frozen_string_literal: true

require "fileutils"
require "net/http"
require "uri"

module Shared
  # TradeDoubler Link Converter, in the engine so every app can attribute.
  #
  # It was inside brgen's `Tradedoubler` service, which is why amber earned
  # nothing: `ShopTheLook#remote_unavailable_reason` answered `:no_feed_client`
  # for every request because that constant is never loaded in amber's process,
  # and `local_links` emitted `link.url` verbatim — no website id, no wrapping.
  # A click that converted paid nobody unless the owner had pasted an
  # already-tracked URL themselves.
  #
  # This half of the client touches no model and no feed: it is an env-var, a URL
  # shape and an EPI string. `Tradedoubler` delegates to it rather than keeping a
  # second copy, because two implementations of an attribution rule is how one of
  # them silently stops attributing.
  module LinkConverter
    ENDPOINT = "https://link.tradedoubler.com/lc"
    SCRIPT_RELATIVE_PATH = "js/td-lc.js"

    module_function

    def website_id
      ENV["TRADEDOUBLER_WEBSITE_ID"].presence
    end

    def configured?
      website_id.present?
    end

    # The remote script, which is also what sync! downloads.
    def remote_script_url
      return nil unless configured?

      "#{ENDPOINT}?a(#{website_id})"
    end

    # Extra Publisher Information — the string TradeDoubler hands back on a
    # conversion, so a sale can be attributed to a city and a surface rather than
    # to "the website". Nil when there is nothing worth recording, so callers can
    # skip the parameter instead of sending an empty one.
    def epi_for(city: nil, surface: nil, tribe: nil, edition: nil, post_id: nil)
      parts = []
      parts << "city:#{city}" if city.present?
      parts << "surface:#{surface}" if surface.present?
      parts << "tribe:#{tribe}" if tribe.present?
      parts << "edition:#{edition}" if edition.present?
      parts << "post:#{post_id}" if post_id.present?
      parts.join("|").presence
    end

    def append_epi(url, epi:, epi2: nil)
      return url if url.blank? || epi.blank?

      uri = URI(url)
      params = URI.decode_www_form(uri.query.to_s)
      params << [ "epi", epi ]
      params << [ "epi2", epi2 ] if epi2.present?
      uri.query = URI.encode_www_form(params)
      uri.to_s
    rescue URI::InvalidURIError
      url
    end

    # Server-side attribution for a merchant URL. OFF by default, deliberately.
    #
    # The verified path is the Link Converter script, because TradeDoubler serves
    # it and it rewrites outbound links itself. This method builds the deep link
    # by hand instead, and the exact Link Converter grammar is not something this
    # repo can confirm without the vendor's current docs — a wrong shape does not
    # degrade to "unattributed", it degrades to a broken link, which is worse than
    # the problem it solves. So it requires TRADEDOUBLER_SERVER_SIDE_WRAP=1 and
    # stays a no-op until somebody has checked one live click through it.
    #
    # It exists because the script is exactly what an ad blocker strips, and on a
    # mobile-first product that is a large share of traffic.
    #
    # Three other guards, each returning the URL unchanged: no website id (an
    # unattributed link still works, and inventing tracking is what
    # affiliate_honesty forbids), an already-tracked URL (double-wrapping breaks
    # the tracking the owner pasted), and a blank URL.
    #
    # EPI is a segment, not a query parameter. Appending it with
    # URI.encode_www_form re-encoded the parentheses in a(…)url(…) and produced
    # `a%2812345%29=` — a link that tracks nothing and goes nowhere. Found by
    # running it rather than by reading it.
    def server_side_wrap_enabled?
      %w[1 true yes on].include?(ENV["TRADEDOUBLER_SERVER_SIDE_WRAP"].to_s.strip.downcase)
    end

    def wrap(url, epi: nil)
      return url if url.blank? || !configured? || !server_side_wrap_enabled?
      return url if already_tracked?(url)

      segments = "a(#{website_id})"
      segments += "epi(#{URI::DEFAULT_PARSER.escape(epi)})" if epi.present?
      "#{ENDPOINT}?#{segments}url(#{URI::DEFAULT_PARSER.escape(url)})"
    end

    def already_tracked?(url)
      host = begin
        URI(url).host.to_s
      rescue URI::InvalidURIError
        ""
      end
      host.end_with?("tradedoubler.com")
    end

    # Ad blockers target tradedoubler.com by hostname, so the script is served
    # from our own origin. An app without its own copy falls back to the remote
    # URL: attribution from a blocked script is zero, and attribution from a
    # first-party copy that no job maintains is stale.
    def local_script_path(root)
      File.join(root.to_s, SCRIPT_RELATIVE_PATH)
    end

    def script_src(public_root)
      return "/#{SCRIPT_RELATIVE_PATH}" if File.exist?(local_script_path(public_root))

      remote_script_url
    end

    def sync!(local_path:)
      remote = remote_script_url
      return false if remote.blank?

      response = Net::HTTP.get_response(URI(remote))
      return false unless response.is_a?(Net::HTTPSuccess)

      FileUtils.mkdir_p(File.dirname(local_path))
      File.binwrite(local_path, response.body)
      true
    rescue StandardError => e
      Rails.logger.warn("link_converter download failed: #{e.class}: #{e.message}")
      false
    end
  end
end
