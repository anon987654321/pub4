# frozen_string_literal: true

# Example Rails controller for demonstration purposes
# In a production application, ensure CSRF protection is enabled
# by using protect_from_forgery with: :exception in ApplicationController
class WelcomeController < ApplicationController
  def index
    @message = "Welcome to Rails!"
    @projects = Project.all
  end

  def show
    @project = Project.find(params[:id])
  end
end
