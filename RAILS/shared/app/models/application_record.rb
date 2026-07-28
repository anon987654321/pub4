# frozen_string_literal: true

class ApplicationRecord < ActiveRecord::Base
  primary_abstract_class
  self.strict_loading_by_default = true
  # Must come before any association is declared: it wraps has_many/has_one so a
  # `dependent: :destroy` cascade can load what it has to delete. See the concern.
  include Shared::CascadingAssociationsLoad
  include Shared::ActivityTrackable
  # Lives here because the trap it exists for is created here: strict loading is
  # on for every environment, and production raises. See the concern.
  include Shared::StrictSafeAssociations
end
