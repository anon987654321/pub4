# frozen_string_literal: true

class MaintainerPortsInfiniteScrollReflex < Shared::InfiniteScrollReflex
  def load_more
    @pagy, @ports = pagy(ports_scope, page: page, request:)
    super
  end

  private

  def page_html
    @ports.map { |port| render(partial: "ports/row", locals: { port: }) }.join
  end

  def ports_scope
    Maintainer.find(element.dataset["maintainerId"]).ports.order(:name).includes(:category)
  end
end
