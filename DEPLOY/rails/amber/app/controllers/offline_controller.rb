# frozen_string_literal: true

class OfflineController < ApplicationController
  allow_unauthenticated_access

  def show
    render layout: false if request.format.html?
  end
end