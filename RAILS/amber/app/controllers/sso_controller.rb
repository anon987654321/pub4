# frozen_string_literal: true

class SsoController < ApplicationController
  include Shared::SsoConsume
  include Shared::SsoUserProvisioning
  allow_unauthenticated_access only: :from_master
end
