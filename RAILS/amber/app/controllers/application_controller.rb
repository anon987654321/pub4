# frozen_string_literal: true

class ApplicationController < ActionController::Base
  include Shared::ApplicationSetup
  include LocalizedRequest
end
