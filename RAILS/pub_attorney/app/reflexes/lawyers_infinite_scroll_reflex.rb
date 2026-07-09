# frozen_string_literal: true

class LawyersInfiniteScrollReflex < Shared::InfiniteScrollReflex
  def load_more
    @pagy, @lawyers = pagy(lawyers_scope, page: page, request:)
    super
  end

  private

  def page_html
    @lawyers.map { |lawyer| render(partial: "lawyers/card", locals: { lawyer: }) }.join
  end

  def lawyers_scope
    scope = Lawyer.order(rating: :desc)
    return scope unless element.dataset["q"].present?

    term = "%#{ActiveRecord::Base.sanitize_sql_like(element.dataset["q"])}%"
    scope.where("name LIKE :q OR specialty LIKE :q OR bio LIKE :q", q: term)
  end
end