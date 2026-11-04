# frozen_string_literal: true

# The page's language, from Accept-Language, for every HTML controller here:
# ApplicationController and ApiController, which does not inherit from it.
module RequestLocale
  extend ActiveSupport::Concern

  # `no` is the macrolanguage tag and several browsers still send it for
  # Norwegian; without the alias it falls through to the default, which happens
  # to be right today and would stop being right the moment the default changes.
  LOCALE_ALIASES = { "no" => :nb, "nn" => :nb }.freeze

  included do
    before_action :set_locale
  end

  private

    # nb unless the browser asks for something this app has.
    #
    # Set per request, not once at boot: I18n.locale is per-thread state that
    # survives into the next request served on the same thread, so one English
    # visitor would otherwise leave the following Norwegian one on :en.
    #
    # The answer depends on that header, so it says so: a cache that ignored
    # Vary would hand the first visitor's language to everyone after.
    def set_locale
      I18n.locale = preferred_locale
      response.headers["Vary"] = [ response.headers["Vary"].presence, "Accept-Language" ].compact.join(", ")
    end

    # Accept-Language, highest q first, matched on the primary subtag so nb-NO
    # and en-GB both land.
    def preferred_locale
      ranked_language_tags.each do |tag|
        primary = tag.split("-").first
        match = I18n.available_locales.find { |locale| locale.to_s == primary } || LOCALE_ALIASES[primary]
        return match if match && I18n.available_locales.include?(match)
      end
      I18n.default_locale
    end

    def ranked_language_tags
      request.get_header("HTTP_ACCEPT_LANGUAGE").to_s.split(",").filter_map do |part|
        tag, quality = part.split(";q=")
        tag = tag.to_s.strip.downcase
        next if tag.empty? || tag == "*"

        [ tag, Float(quality || 1, exception: false) || 0.0 ]
      end.sort_by { |pair| -pair.last }.map(&:first)
    end
end
