# frozen_string_literal: true

class RobotsController < ApplicationController
  def show
    render plain: catalog.robots_txt
  end
end