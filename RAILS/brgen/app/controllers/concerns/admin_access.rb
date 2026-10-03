# frozen_string_literal: true

# The one admin: the account named by BRGEN_ADMIN_EMAIL, with its email
# verified. Every site-wide review queue asks this, so there is one place to get
# wrong who may read other people's reports and business papers.
module AdminAccess
  extend ActiveSupport::Concern

  private

  def require_admin!
    expected = ENV["BRGEN_ADMIN_EMAIL"].to_s.strip
    if expected.present? && Current.user&.email_address == expected
      return if !Current.user.respond_to?(:email_verified?) || Current.user.email_verified?
    end

    redirect_to(main_app.root_path, alert: t("shared.flash.not_authorized"))
  end
end
