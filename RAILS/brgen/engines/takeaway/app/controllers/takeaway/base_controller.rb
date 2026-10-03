# frozen_string_literal: true

# Namespace hook for takeaway/* — keep empty until shared vertical policy/layout lands.
class Takeaway::BaseController < ApplicationController
  include Shared::FindableBySlug # restaurants are slug-routed; nested lookups resolve slug-or-id
end
