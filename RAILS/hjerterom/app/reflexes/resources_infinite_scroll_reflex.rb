# frozen_string_literal: true

class ResourcesInfiniteScrollReflex < Shared::InfiniteScrollReflex
  def load_more
    @pagy, @resources = pagy(resources_scope, page: page, request:)
    super
  end

  private

  def page_html
    @resources.map { |resource| render(partial: "resources/card", locals: { resource: }) }.join
  end

  def resources_scope
    scope = Resource.includes(:category).verified.order(:title)
    scope = scope.by_type(element.dataset["kind"]) if element.dataset["kind"].present?
    return scope unless element.dataset["q"].present?

    term = "%#{ActiveRecord::Base.sanitize_sql_like(element.dataset["q"])}%"
    scope.where("title LIKE :q OR description LIKE :q OR resource_type LIKE :q", q: term)
  end
end