# frozen_string_literal: true

class ApplicationRecord < ActiveRecord::Base
  primary_abstract_class
  self.strict_loading_by_default = true
  include Shared::ActivityTrackable
  # Lives here because the trap it exists for is created here: strict loading is
  # on for every environment, and production raises. See the concern.
  include Shared::StrictSafeAssociations
end
