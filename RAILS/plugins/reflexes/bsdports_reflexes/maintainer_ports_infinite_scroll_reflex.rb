# frozen_string_literal: true

class MaintainerPortsInfiniteScrollReflex < Shared::InfiniteScrollReflex
  renders "ports/row", as: :port

  private

  def scope
    Maintainer.find(element.dataset["maintainerId"]).ports.order(:name).includes(:category)
  end
end
