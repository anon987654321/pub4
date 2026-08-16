# frozen_string_literal: true

# `in_current_city` for models with no city of their own, which reach one
# through a belongs_to: Tv::Video and Tv::Broadcast via :channel,
# Marketplace::Deal via :listing.
#
# acts_as_tenant cannot help these — there is no city_id to scope — so without
# a scope they are simply unscoped, and one city's rows appear on every other
# city's pages. That is not hypothetical: it is the tv.oshlo.no 500 of
# 2026-08-12 (see Tv::ChannelTenanted, which this generalises) and it was still
# true of Marketplace::Deal on every city sitemap until this concern existed.
#
# The association is resolved lazily inside the scope so declaring it does not
# force the associated class to load at class-definition time.
module TenantedThrough
  extend ActiveSupport::Concern

  class_methods do
    def tenanted_through(association)
      scope :in_current_city, lambda {
        tenant = ActsAsTenant.current_tenant
        next all unless tenant

        parent = klass.reflect_on_association(association).klass
        joins(association).where(parent.table_name => { city_id: [ tenant.id, nil ] })
      }
    end
  end
end
