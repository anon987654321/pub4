# frozen_string_literal: true

# Namespace hook for marketplace/* — keep empty until shared vertical policy/layout lands.
class Marketplace::BaseController < ApplicationController
  include Shared::FindableBySlug # listings/stores are slug-routed; nested lookups resolve slug-or-id
end
