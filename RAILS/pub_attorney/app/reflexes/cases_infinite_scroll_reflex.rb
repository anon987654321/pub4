# frozen_string_literal: true

class CasesInfiniteScrollReflex < Shared::InfiniteScrollReflex
  def load_more
    @pagy, @cases = pagy(cases_scope, page: page, request:)
    super
  end

  private

  def page_html
    @cases.map { |kase| render(partial: "cases/card", locals: { kase: }) }.join
  end

  def cases_scope
    scope = Current.user.cases.includes(:lawyer).order(created_at: :desc)
    return scope unless element.dataset["q"].present?

    term = "%#{ActiveRecord::Base.sanitize_sql_like(element.dataset["q"])}%"
    scope.where("title LIKE :q OR status LIKE :q OR description LIKE :q", q: term)
  end
end