# frozen_string_literal: true

# Namespace hook for tv/* — keep empty until shared vertical policy/layout lands.
class Tv::BaseController < ApplicationController
  include Shared::FindableBySlug # videos are slug-routed; nested lookups resolve slug-or-id
end
