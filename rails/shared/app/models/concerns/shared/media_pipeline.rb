# frozen_string_literal: true

module Shared
  module MediaPipeline
    extend ActiveSupport::Concern

    class_methods do
      def has_optimized_attachment(name)
        define_method("#{name}_variant") do |profile = :feed|
          return nil unless send(name).attached?
          dims = profile == :thumb ? [150, 150] : [800, 600]
          send(name).variant(resize_to_limit: dims, saver: { strip: true, quality: 82 })
        end
      end
    end
  end
end
