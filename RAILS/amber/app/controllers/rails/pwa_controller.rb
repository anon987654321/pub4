# frozen_string_literal: true

module Rails
  # The actions live in Shared::PwaServing. Rails resolves this constant by bare
  # name, so the class has to exist in each app; what belongs to the app is the
  # copy on its offline page.
  class PwaController < ApplicationController
    include Shared::PwaServing

    private

    def pwa_app_name = "Amber"
    def pwa_storage_key = "amber"
  end
end
