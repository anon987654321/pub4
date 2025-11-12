# frozen_string_literal: true

class ApplicationController < ActionController::Base
  # Enable CSRF protection for all controllers
  protect_from_forgery with: :exception
end
