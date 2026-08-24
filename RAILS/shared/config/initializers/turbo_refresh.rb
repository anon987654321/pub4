# frozen_string_literal: true

# ApplicationController calls +turbo_refreshes_with+ at class level; turbo-rails only
# defines the helper for views. Bridge the DSL to per-request meta tags in :head.
ActiveSupport.on_load(:action_controller_base) do
  def self.turbo_refreshes_with(method = :replace, scroll: :reset)
    before_action do
      helpers.turbo_refreshes_with(method:, scroll:)
    end
  end
end
