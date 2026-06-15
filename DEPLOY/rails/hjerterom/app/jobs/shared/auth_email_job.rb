# frozen_string_literal: true

module Shared
  class AuthEmailJob < ApplicationJob
    include Shared::ExternalApiRetry

    queue_as :critical

    def perform(mailer_class, mail_method, *args)
      mailer_class.constantize.public_send(mail_method, *args).deliver_now
    end
  end
end