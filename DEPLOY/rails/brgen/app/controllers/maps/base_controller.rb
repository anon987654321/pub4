# frozen_string_literal: true

module Maps
  class BaseController < ApplicationController
    allow_unauthenticated_access
  end
end
