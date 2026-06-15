# frozen_string_literal: true

module Shared
  module SearchIndex
    module_function

    def rebuild!(model_name = nil)
      models = model_name ? [model_name.constantize] : []
      models.each { |model| model.rebuild_search_index! if model.respond_to?(:rebuild_search_index!) }
    end
  end
end