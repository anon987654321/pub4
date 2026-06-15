# frozen_string_literal: true

module Shared
  class SuspiciousLoginMailer < ApplicationMailer
    def new_country_alert(user, country, previous)
      @user = user
      @country = country
      @previous = previous
      mail(to: user.email_address, subject: "New sign-in location detected")
    end
  end
end