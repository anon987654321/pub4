# frozen_string_literal: true

module Shared
  # The community rules, in the order the first brgen gave them (2015): what
  # nobody may do, what not to post, and impersonation. The words live in
  # config/locales/rules.*.yml under legal.rules_page. The 2015 page also made
  # users liable for damages and pre-authorised releasing an impersonator's
  # data; those were legal terms, not community rules, and stay out.
  module Rules
    RULE_SECTIONS = {
      forbidden: %w[multiple_accounts url_shorteners harvesting copying automated_access harm],
      posting: %w[illegal affiliate_marketing wrong_category repeats on_behalf automated_posting],
      impersonation: %w[pretending],
    }.freeze

    def rules_sections
      safe_join(RULE_SECTIONS.map do |section, keys|
        items = keys.map { |key| tag.li(t("#{section}.#{key}", scope: "legal.rules_page")) }
        tag.h2(t("legal.rules_page.#{section}_heading")) + tag.ul(safe_join(items))
      end)
    end
  end
end
