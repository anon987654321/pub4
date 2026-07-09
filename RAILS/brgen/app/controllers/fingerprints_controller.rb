# frozen_string_literal: true

class FingerprintsController < ApplicationController
  include Shared::FingerprintsActions

  allow_unauthenticated_access only: :create
  skip_before_action :verify_authenticity_token, only: :create
end