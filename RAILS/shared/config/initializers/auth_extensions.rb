# frozen_string_literal: true

Rails.application.config.to_prepare do
  next unless defined?(::User) && ::User < ApplicationRecord

  ::User.include(Shared::UserAuthExtensions) unless ::User.included_modules.include?(Shared::UserAuthExtensions)
end
