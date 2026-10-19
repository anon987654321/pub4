# frozen_string_literal: true

# Which language amber answers in.
#
# `config.i18n.available_locales = %i[nb en]` and `default_locale = :nb` have
# been set since the app was built, but nothing ever read Accept-Language and
# there was no switcher anywhere — so every visitor got Norwegian and the whole
# English half of the locale files was unreachable. Four hundred keys that CI
# kept at parity and no user could ever see.
#
# Precedence, most explicit first:
#
#   ?locale=en        an explicit switch, remembered in the session
#   session[:locale]  what you last chose
#   Accept-Language   what the browser asked for, by quality
#   I18n.default_locale (:nb) — amber is a Bergen wardrobe
#
# Session rather than a users column: no migration, and it works for the
# signed-out demo wardrobe too. A per-account preference would need a column
# and would only help across devices.
module LocalizedRequest
  extend ActiveSupport::Concern

  included do
    around_action :switch_locale
    helper_method :current_locale, :available_locales, :locale_url
  end

  private

  # Stay on the page you are reading, in the other language. Built from the
  # request path rather than url_for: after a failed create the action is
  # `create`, and url_for would happily generate the index path instead of the
  # form you are looking at. Non-GET pages fall back to root, which is the only
  # honest answer for a URL you cannot re-request.
  def locale_url(locale)
    # GET and HEAD, not request.get?: HEAD routes like GET but request.get? is
    # false for it, which would send a HEAD-rendered page's switcher to root.
    base = %w[GET HEAD].include?(request.request_method) ? request.path : root_path
    query = request.query_parameters.merge(locale: locale).to_query
    "#{base}?#{query}"
  end

  def switch_locale(&)
    session[:locale] = requested_locale.to_s if requested_locale
    I18n.with_locale(current_locale, &)
  end

  def current_locale
    @current_locale ||= supported(session[:locale]) || browser_locale || I18n.default_locale
  end

  def available_locales = I18n.available_locales

  def requested_locale = supported(params[:locale])

  def supported(locale)
    return nil if locale.blank?

    symbol = locale.to_s.to_sym
    I18n.available_locales.include?(symbol) ? symbol : nil
  end

  # "nb-NO,nb;q=0.9,en;q=0.8" — highest quality amber can actually serve.
  # Region subtags are dropped on the second pass so en-GB counts as en.
  def browser_locale
    ranked_languages.filter_map { |tag| supported(tag) || supported(tag.split("-").first) }.first
  end

  def ranked_languages
    request.get_header("HTTP_ACCEPT_LANGUAGE").to_s.split(",").filter_map { |part|
      tag, quality = part.split(";q=")
      tag = tag.to_s.strip
      next if tag.blank? || tag == "*"

      [ tag, (quality || "1").to_f ]
    }.sort_by { |_tag, quality| -quality }.map(&:first)
  end
end
