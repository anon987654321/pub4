# frozen_string_literal: true

module Ground
  module Swallow
    module_function

    def log(error, context:, **metadata)
      if defined?(::Master::Ground::Swallow)
        ::Master::Ground::Swallow.log(error, context:, **metadata)
      else
        Rails.logger.warn(
          "swallow:error context=#{context} #{error.class}: #{error.message} #{metadata.inspect}",
        )
      end
      nil
    end
  end
end
