# frozen_string_literal: true

require "open3"

module Ports
  # What pkg_info says about one package on this host. nil means it could not
  # be asked (a host without pkg_info) and the page says unknown; "" means not
  # installed, since a non-zero exit's message is not installation info.
  #
  # Each port view forked pkg_info; the answer is cached per package for a few
  # minutes, which a pkg_add on the host outdates no faster than a reader notices.
  class LocalPackage
    TTL = 5.minutes

    def self.info(name, cache: Rails.cache)
      cache.fetch([ "bsdports", "pkg_info", name ], expires_in: TTL, skip_nil: true) { ask(name) }
    end

    def self.ask(name)
      out, status = Open3.capture2e("pkg_info", "-q", name)
      status.success? ? out.strip : ""
    rescue SystemCallError => e
      Rails.logger.info("pkg_info unavailable: #{e.class}")
      nil
    end
  end
end
