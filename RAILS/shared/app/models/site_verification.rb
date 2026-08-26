# frozen_string_literal: true

# Per-domain ownership tokens, parsed once from the environment.
#
# Format, chosen so one variable covers every domain and network:
#
#   SITE_VERIFICATION="brgen.no:tradedoubler=abc123,google=xyz789;oshlo.no:tradedoubler=def456"
#
#   domains separated by ";"   host and its pairs separated by ":"
#   pairs separated by ","     network and token separated by "="
#
# Never a file in the repo. A verification token is a shared secret with the
# network -- committing one lets anyone who can read this tree claim the domain,
# and this repo is read by several agents.
#
# Unparseable entries are dropped rather than raised on. A malformed token would
# otherwise take the whole site down at boot to protect a marketing integration,
# which is the wrong trade; the failure it causes instead is a 404 on one
# verification URL, which is exactly where someone will be looking.
class SiteVerification
  NETWORK = /\A[a-z0-9_-]{2,32}\z/
  TOKEN = /\A[A-Za-z0-9_.:-]{4,128}\z/

  class << self
    def token_for(host, network)
      return nil unless network.to_s.match?(NETWORK)

      table.dig(normalize(host), network.to_s)
    end

    def networks_for(host)
      table.fetch(normalize(host), {})
    end

    def reload!
      @table = nil
      table
    end

    private

    def table
      @table ||= parse(ENV["SITE_VERIFICATION"].to_s)
    end

    # www and case are stripped so a token set for brgen.no also answers on
    # WWW.Brgen.No -- the network decides which it fetches and it is not worth
    # a denial to be strict about it.
    def normalize(host)
      host.to_s.downcase.strip.delete_prefix("www.")
    end

    def parse(raw)
      raw.split(";").each_with_object({}) do |chunk, acc|
        host, pairs = chunk.split(":", 2)
        next if host.nil? || pairs.nil?

        host = normalize(host)
        next if host.empty?

        entries = pairs.split(",").filter_map do |pair|
          network, token = pair.split("=", 2)
          network = network.to_s.strip.downcase
          token = token.to_s.strip
          next unless network.match?(NETWORK) && token.match?(TOKEN)

          [ network, token ]
        end
        acc[host] = entries.to_h if entries.any?
      end
    end
  end
end
