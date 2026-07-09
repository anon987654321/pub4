# frozen_string_literal: true

class BeneficiariesInfiniteScrollReflex < Shared::InfiniteScrollReflex
  def load_more
    @pagy, @beneficiaries = pagy(beneficiaries_scope, page: page, request:)
    super
  end

  private

  def page_html
    @beneficiaries.map { |beneficiary| render(partial: "beneficiaries/row", locals: { beneficiary: }) }.join
  end

  def beneficiaries_scope
    Beneficiary.active.priority_first
  end
end