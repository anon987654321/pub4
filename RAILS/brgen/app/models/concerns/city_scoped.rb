# frozen_string_literal: true

# `in_current_city` for models that carry their own city_id.
#
# acts_as_tenant already puts a default_scope on every CityTenantable model, and
# that scoping is real — but a default_scope is invisible at the call site, and
# the surfaces that hand a list of records to something outside the request
# (the sitemap, a feed export) are exactly where a reader needs to see the city
# named. This is that name. On a tenanted model it is redundant with the
# default scope by design; on Place, which has the column but not the concern,
# it is the only scoping there is.
#
# nil city_id is included deliberately, matching Tv::ChannelTenanted: the
# tenant declaration is `optional: true`, so a row with no city is legal and
# reads as global — it belongs in every city, not in none.
module CityScoped
  extend ActiveSupport::Concern

  included do
    scope :in_current_city, lambda {
      tenant = ActsAsTenant.current_tenant
      next all unless tenant

      where(city_id: [ tenant.id, nil ])
    }
  end
end
