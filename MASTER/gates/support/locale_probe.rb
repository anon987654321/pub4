# frozen_string_literal: true

require "uri"
require_relative "cdp_session"
require_relative "geometry_probe"

module Deploy
  # The same surface in each locale the apps ship. Locale is chosen four ways
  # across the trees: amber answers ?locale= then its session then
  # Accept-Language, master_web reads Accept-Language, and brgen resolves it from
  # the request host (brgen.no is nb, lsangeles.com is en). The probe sends the
  # query and the header together and then reads <html lang>, so a surface that
  # cannot change language on this host says so instead of being compared with
  # itself. Only the resting state is walked for the extra locale.
  module LocaleProbe
    DEFAULT = "nb,en"
    LANG_JS = "(document.documentElement.getAttribute('lang') || '').toLowerCase()"
    TEXTS_LIMIT = 300

    module_function

    def wanted
      ENV.fetch("MASTER_VISUAL_LOCALES", DEFAULT).split(",").map { |c| normalize(c) }.reject(&:empty?).uniq
    end

    def normalize(code)
      base = code.to_s.strip.downcase.split(/[-_]/).first.to_s
      %w[no nn].include?(base) ? "nb" : base
    end

    # payload["locales"] = {"nb" => {"lang", "texts" => {key => [text, tag]}}, "en" => {...} | {"status" => "unavailable"}}
    def attach(cdp, surface, payload)
      return payload unless payload.is_a?(Hash) && !payload["error"] && wanted.size > 1

      primary = normalize(cdp.evaluate(LANG_JS))
      rows = { (primary.empty? ? "unknown" : primary) => { "lang" => primary, "texts" => texts(payload["elements"]) } }
      extra = wanted - [primary]
      return payload.merge("locales" => rows) if extra.empty?

      extra.each { |code| rows[code] = fetch(cdp, surface, code) }
      restore(cdp, surface)
      payload.merge("locales" => rows)
    rescue CdpSession::Error => e
      payload.merge("locales_error" => "#{e.class.name.split("::").last} #{e.message[0, 80]}")
    end

    def fetch(cdp, surface, code)
      cdp.headers("Accept-Language" => code)
      cdp.clear_cookies
      cdp.navigate(with_locale(surface.url, code))
      lang = normalize(cdp.evaluate(LANG_JS))
      return { "status" => "unavailable", "lang" => lang } unless lang == code

      { "lang" => lang, "texts" => texts(cdp.evaluate(GeometryProbe::WALK)["elements"]) }
    end

    def with_locale(url, code)
      uri = URI(url)
      uri.query = [uri.query, "locale=#{code}"].compact.join("&")
      uri.to_s
    end

    # The page goes back to the language and cookies the baseline was taken in,
    # so the probes that follow measure the surface the critique will see.
    def restore(cdp, surface)
      cdp.headers(GeometryProbe::PROBE_HEADERS)
      cdp.clear_cookies
      cdp.navigate(surface.url)
    end

    def texts(elements)
      Array(elements).select { |e| e["visible"] != false && e["text"].to_s.strip != "" }.first(TEXTS_LIMIT)
                     .to_h { |e| [e["key"], [e["text"].to_s.strip, e["tag"]]] }
    end
  end
end
