# frozen_string_literal: true

module Shared
  module PagyPagination
    extend ActiveSupport::Concern

    if defined?(Pagy::Method)
      include Pagy::Method
    else
      include Pagy::Backend
    end
  end
end
