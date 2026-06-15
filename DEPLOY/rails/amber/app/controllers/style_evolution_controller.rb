# frozen_string_literal: true

class StyleEvolutionController < ApplicationController
  before_action :require_authentication

  def show
    @timeline = StyleEvolutionService.timeline_for(Current.user)
  end
end