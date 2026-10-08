# frozen_string_literal: true

# The parent of every tv/* controller. Videos, channels and shows are slug-routed,
# so nested lookups resolve slug-or-id here once.
class Tv::BaseController < ApplicationController
  include Shared::FindableBySlug # videos are slug-routed; nested lookups resolve slug-or-id
end
