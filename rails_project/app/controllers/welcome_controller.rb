# frozen_string_literal: true

class WelcomeController < ApplicationController
  def index
    @message = "Welcome to Rails!"
    @projects = Project.all
  end

  def show
    @project = Project.find(params[:id])
  end
end
