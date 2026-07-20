# frozen_string_literal: true

module CityTenantable
  extend ActiveSupport::Concern

  included do
    acts_as_tenant :city, optional: true
    belongs_to :city, optional: true
    before_validation :assign_current_city, on: :create
  end

  private

  def assign_current_city
    self.city ||= ActsAsTenant.current_tenant
  end
end
