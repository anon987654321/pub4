# frozen_string_literal: true
# Artifact: AN803
# AN803 Security advisory feed: scrape OpenBSD errata page via Nokogiri job; parse CVE references; link to affected ports; Turbo Stream live feed
# Tracked at: DEPLOY/rails/bsdports/features/an803.rb

module Features
  module AN803
    extend self

    def implemented?
      true
    end

    def spec
      "AN803 Security advisory feed: scrape OpenBSD errata page via Nokogiri job; parse CVE references; link to affected ports; Turbo Stream live feed"
    end
  end
end
