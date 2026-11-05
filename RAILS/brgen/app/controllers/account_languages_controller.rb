# frozen_string_literal: true

# The language switch on the account page. A chosen language follows the
# account to every device and city domain; "follow the site" (blank) clears it,
# so the domain decides again (brgen.no is nb).
class AccountLanguagesController < ApplicationController
  before_action :require_user_session
  rate_limit to: 20, within: 10.minutes, only: :update, name: "account_language", by: -> { "u#{Current.user&.id}" }

  # "" follows the site; the rest are the locales brgen ships.
  CHOICES = [ "", *I18n.available_locales.collect(&:to_s) ].freeze

  def update
    choice = params[:locale].to_s
    return head(:unprocessable_content) unless CHOICES.include?(choice)

    Current.user.update!(locale: choice.presence)
    locale = choice.presence || site_locale
    redirect_to account_path, notice: t("account_language.saved", locale:)
  end
end
