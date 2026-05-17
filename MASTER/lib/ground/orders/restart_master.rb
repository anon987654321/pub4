# frozen_string_literal: true

require "open3"

module Master
  module Ground
  module Orders
    class RestartMaster < Base
      def call
        _, status = Open3.capture2e("doas", "rcctl", "restart", "master")
        status.success? ? Result.ok(restarted: true) : Result.err("rcctl restart failed")
      rescue StandardError => e
        Result.err(e.message)
      end
    end
  end
  end
end
