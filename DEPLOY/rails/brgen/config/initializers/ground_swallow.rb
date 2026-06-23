# frozen_string_literal: true

# Tolerated-failure logging for brgen (scan canon: Ground::Swallow.log).
# Delegates to MASTER when loaded; otherwise logs via Rails.logger.
module Ground
  module Swallow
    module_function

    def log(error, context:, **metadata)
      if defined?(::Master::Ground::Swallow)
        ::Master::Ground::Swallow.log(error, context: context, **metadata)
      else
        Rails.logger.warn(
          "swallow:error context=#{context} #{error.class}: #{error.message} #{metadata.inspect}"
        )
      end
      nil
    end
  end
end