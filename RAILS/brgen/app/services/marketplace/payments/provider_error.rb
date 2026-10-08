# frozen_string_literal: true

module Marketplace
  module Payments
    # A payment provider answered with a refusal or something unreadable. Its
    # own class so a checkout can tell a PSP failure from a defect in our code.
    # A RuntimeError, as the bare raise it stands for is, so every existing
    # rescue still catches it.
    class ProviderError < RuntimeError; end
  end
end
