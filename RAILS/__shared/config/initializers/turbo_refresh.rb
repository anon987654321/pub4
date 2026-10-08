# frozen_string_literal: true

# ApplicationController declares +turbo_refreshes_with+ at class level; turbo-rails
# only defines the helper for views, where it provides the two meta tags to :head.
#
# The declaration is applied to the view context a render builds. The
# controller's `helpers` proxy is a different view context from the one that
# renders the layout, so tags provided there reach no page, and Turbo then
# refreshes with its defaults: replace, and scroll to the top.
ActiveSupport.on_load(:action_controller_base) do
  class_attribute :turbo_refresh_preference, instance_writer: false, default: nil

  def self.turbo_refreshes_with(method = :replace, scroll: :reset)
    self.turbo_refresh_preference = { method:, scroll: }
  end

  def view_context
    super.tap do |view|
      view.turbo_refreshes_with(**turbo_refresh_preference) if turbo_refresh_preference
    end
  end
end
