# frozen_string_literal: true

module Shared
  # The safety page's advice, in the order the first brgen gave it. The words
  # live in config/locales/safety.*.yml under legal.safety_page; this names the
  # entries of each section and the sites worth knowing.
  module Safety
    SAFETY_SECTIONS = {
      dating: %w[meet_in_public no_strangers_home carry_phone bring_friend tell_someone],
      trading: %w[deal_locally no_transfers no_links no_gifts no_proxy_ads research trust_gut],
      health: %w[not_medical_html no_liability_html ask_doctor_html emergency_html helpline_html],
    }.freeze

    SAFETY_SITES = {
      "slettmeg.no" => "slettmeg", "dubestemmer.no" => "dubestemmer", "nettvett.no" => "nettvett",
      "norsis.no" => "norsis", "forbrukertilsynet.no" => "forbrukertilsynet", "datatilsynet.no" => "datatilsynet",
    }.freeze

    POLICE_CONTACT = "https://www.politiet.no/kontakt-politiet/"

    def safety_intro
      police = link_to(t("legal.safety_page.police"), POLICE_CONTACT)
      tag.p t("legal.safety_page.intro_html", police:)
    end

    def safety_sections
      safe_join(SAFETY_SECTIONS.map do |section, keys|
        items = keys.map { |key| tag.li(t("#{section}.#{key}", scope: "legal.safety_page")) }
        tag.h2(t("legal.safety_page.#{section}_heading")) + tag.ul(safe_join(items))
      end)
    end

    def safety_sites
      items = SAFETY_SITES.map do |host, key|
        tag.li(safe_join([ link_to(host, "https://#{host}", rel: "noopener"), " ",
                          tag.small(t(key, scope: "legal.safety_page.sites")) ]))
      end
      tag.h2(t("legal.safety_page.sites_heading")) + tag.ul(safe_join(items))
    end
  end
end
