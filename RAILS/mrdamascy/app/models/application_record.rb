# frozen_string_literal: true

class ApplicationRecord < ActiveRecord::Base
  primary_abstract_class

  # MASTER's strict-loading law (every environment) is deliberately not
  # enabled yet: OrdersController, ReviewsController, Staff::BoardController#advance,
  # ApplicationController#current_user and several test helpers still lazy-load
  # associations (order_items, review, Session#user), and this checkout cannot
  # run `rails test` here to prove each site preloads first. Flip
  # strict_loading_by_default = true in the same commit that adds those
  # includes — enabling it alone would 500 the lazy sites it is meant to guard.
  # self.strict_loading_by_default = true
end
