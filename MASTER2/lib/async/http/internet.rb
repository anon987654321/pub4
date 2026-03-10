# frozen_string_literal: true

module Async
  module HTTP
    class Internet
      Response = Struct.new(:status, :body) do
        def read = body
      end

      def get(_url, _headers = [])
        Response.new("503", "")
      end

      def close; end
    end
  end
end
