# frozen_string_literal: true

module CityTenantable
  extend ActiveSupport::Concern

  included do
    # in_current_city: the same scoping acts_as_tenant applies by default, but
    # named, for the surfaces where a reader has to be able to see it.
    include CityScoped

    acts_as_tenant :city, optional: true
    belongs_to :city, optional: true
    before_validation :assign_current_city, on: :create
  end

  private

  def assign_current_city
    self.city ||= ActsAsTenant.current_tenant
  end
end
