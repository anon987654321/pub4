# frozen_string_literal: true

module Shared
  # Beautiful, stable URL slugs from a title/name, following the inline pattern
  # tv/channel and tv/show already use — extracted so posts, listings, videos,
  # restaurants and tracks share one implementation instead of five copies.
  #
  #   class Post < ApplicationRecord
  #     include Shared::Sluggable
  #     sluggable_from :title            # defaults to :title
  #   end
  #
  # Uniqueness is scoped to the tenant column when present (acts_as_tenant on
  # :city_id), so two cities can each have a "sol-pa-floyen" without colliding, and
  # a duplicate within a city gets a numeric suffix. `to_param` returns the slug so
  # routes read /posts/sol-pa-floyen; controllers still find_by(slug:) or by id for
  # old links (see Shared::FindableBySlug).
  module Sluggable
    extend ActiveSupport::Concern

    included do
      before_validation :assign_slug
      validates :slug, presence: true,
                       format: { with: /\A[a-z0-9][a-z0-9\-]*\z/, message: "must be url-safe" }
      validates :slug, uniqueness: { scope: (column_names.include?("city_id") ? :city_id : nil) }
    end

    class_methods do
      def sluggable_from(attr) = @sluggable_source = attr.to_sym
      def sluggable_source = @sluggable_source || :title
    end

    def to_param = slug.presence || id.to_s

    private

    def assign_slug
      return if slug.present?

      source = self.class.sluggable_source
      base = respond_to?(source) ? send(source).to_s.parameterize : ""
      base = "item" if base.blank?

      scope = self.class.unscoped
      scope = scope.where(city_id:) if respond_to?(:city_id) && city_id.present?
      scope = scope.where.not(id:) if persisted?

      candidate = base
      suffix = 2
      while scope.exists?(slug: candidate)
        candidate = "#{base}-#{suffix}"
        suffix += 1
      end
      self.slug = candidate
    end
  end
end
