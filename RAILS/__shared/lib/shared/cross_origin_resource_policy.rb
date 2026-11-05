# frozen_string_literal: true

module Shared
  # Cross-Origin-Resource-Policy is same-origin by default (security_headers.rb):
  # another site cannot pull a page or a JSON answer into its own process as a
  # no-cors resource. Images and Active Storage files are the exception and say
  # cross-origin, because they are meant to be embedded elsewhere: a newsletter
  # image is loaded by the reader's webmail from the mail provider's origin, and
  # the city domains (brgen.no, lsangeles.com and the rest) are separate sites
  # that show each other's photos. same-site would block both.
  class CrossOriginResourcePolicy
    HEADER = "cross-origin-resource-policy"
    SHAREABLE_PATH = "/rails/active_storage/"

    def initialize(app)
      @app = app
    end

    def call(env)
      status, headers, body = @app.call(env)
      headers[HEADER] = "cross-origin" if headers[HEADER] && shareable?(env, headers)
      [ status, headers, body ]
    end

    private

    def shareable?(env, headers)
      env["PATH_INFO"].to_s.start_with?(SHAREABLE_PATH) || headers["content-type"].to_s.start_with?("image/")
    end
  end
end
