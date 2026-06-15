# frozen_string_literal: true

module Shared
  class AccountExportJob < ApplicationJob
    queue_as :bulk

    def perform(user_id)
      user = User.find(user_id)
      csv = Shared::AccountExporter.to_csv(user)
      Shared::AccountExportMailer.ready(user, csv).deliver_later
    end
  end
end