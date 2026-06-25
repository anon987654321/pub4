# frozen_string_literal: true

module Authentication
  def self.included(base)
    base.include(Shared::Authentication)
  end
end
