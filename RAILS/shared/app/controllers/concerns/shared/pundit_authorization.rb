# frozen_string_literal: true

module Shared
  module PunditAuthorization
    extend ActiveSupport::Concern
    include Pundit::Authorization

    included do
      rescue_from Pundit::NotAuthorizedError, with: :user_not_authorized
    end

    private

    def user_not_authorized
      redirect_to root_path, alert: t("shared.flash.not_authorized")
    end
  end
end
