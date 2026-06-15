# frozen_string_literal: true

module Shared
  module CacheableShow
    extend ActiveSupport::Concern

    private

    def respond_to_cached_show(record, public: true, **json_options)
      fresh_when(record, public: public)

      respond_to do |format|
        format.html
        format.json { render json: record.as_json(json_options) }
      end
    end
  end
end