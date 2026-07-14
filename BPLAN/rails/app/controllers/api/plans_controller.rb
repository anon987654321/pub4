# frozen_string_literal: true

module Api
  class PlansController < ApplicationController
    def index
      render json: catalog.plans_json
    end
  end
end