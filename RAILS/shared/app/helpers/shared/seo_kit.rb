# frozen_string_literal: true

module Shared
  # Cross-app SEO, affiliate, and permission-marketing helpers.
  module SeoKit
    DEFAULT_DISCLOSURE = "Some links are affiliate links. We may earn a commission at no extra cost to you."

    def meta_description_for(resource, fallback: nil)
      text = resource.try(:meta_description) ||
             resource.try(:description) ||
             resource.try(:content) ||
             resource.try(:body) ||
             resource.try(:bio)
      strip_tags(text.to_s).squish.truncate(160).presence || fallback
    end

    def seo_canonical_url(url = request.original_url)
      url.to_s.split("?").first
    end

    def affiliate_disclosure_text
      DEFAULT_DISCLOSURE
    end

    # Publisher verification (TradeDoubler support thread, 2026-08-07). Their
    # local publisher team proves site ownership by loading a page that clearly
    # displays the account's Site ID, and asks for a visible contact email and a
    # reachable cookie policy on the same site. All three have to be on a page a
    # stranger can load without signing in, which is why they render in the site
    # legal footer rather than on an account or admin surface.
    #
    # Deliberately NOT gated on TRADEDOUBLER_TOKEN like the partner list below:
    # the token is issued *after* approval, and this is what gets you approved.
    # Gating it on the token would have hidden it for exactly as long as it was
    # needed.
    def tradedoubler_site_id
      ENV["TRADEDOUBLER_SITE_ID"].presence
    end

    # No default. An invented address on a verification page is worse than none:
    # the reviewer mails it, it bounces, and the application fails for a reason
    # nobody can see from here.
    def site_contact_email
      ENV["SITE_CONTACT_EMAIL"].presence
    end

    def amazon_affiliate_url(url_or_asin)
      target = url_or_asin.to_s.strip
      return target if AMAZON_TAG.blank?

      if target.match?(%r{\Ahttps?://})
        uri = URI.parse(target)
        params = URI.decode_www_form(uri.query.to_s).to_h
        params["tag"] = AMAZON_TAG
        uri.query = URI.encode_www_form(params)
        uri.to_s
      else
        "https://www.amazon.com/dp/#{target}?tag=#{AMAZON_TAG}"
      end
    rescue URI::InvalidURIError
      target
    end

    def organization_json_ld(site_name:, url:, logo: nil)
      {
        "@context" => "https://schema.org",
        "@type" => "Organization",
        "name" => site_name,
        "url" => url,
        "logo" => logo,
      }.compact
    end

    def website_json_ld(site_name:, url:, description: nil)
      {
        "@context" => "https://schema.org",
        "@type" => "WebSite",
        "name" => site_name,
        "url" => url,
        "description" => description,
        "potentialAction" => {
          "@type" => "SearchAction",
          "target" => "#{url}/search?q={search_term_string}",
          "query-input" => "required name=search_term_string",
        },
      }.compact
    end

    def breadcrumb_json_ld(items)
      {
        "@context" => "https://schema.org",
        "@type" => "BreadcrumbList",
        "itemListElement" => items.each_with_index.map { |(name, item_url), index|
          {
            "@type" => "ListItem",
            "position" => index + 1,
            "name" => name,
            "item" => item_url,
          }
        },
      }
    end

    def json_ld_script(data)
      return "" if data.blank?

      tag.script(data.to_json.html_safe, type: "application/ld+json", data: { turbo_permanent: true })
    end

    def robots_meta(index: true, follow: true)
      directives = []
      directives << (index ? "index" : "noindex")
      directives << (follow ? "follow" : "nofollow")
      tag.meta(name: "robots", content: directives.join(", "))
    end
  end
end
