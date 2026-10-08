# frozen_string_literal: true

# Records the browser fingerprint pub4/browser_fingerprint computes, as the
# signed permanent cookie Shared::AnonymousPost reads back to bound anonymous
# posting.
#
# Top-level rather than Shared::FingerprintsController because the host route
# is `post "fingerprint" => "fingerprints#create"`, which resolves a bare
# constant — the shape AccountSettingsController and OmniauthCallbacksController
# already use. Only the apps that mount the Stimulus controller draw the route.
class FingerprintsController < ::ApplicationController
  include Shared::FingerprintsActions

  allow_unauthenticated_access only: :create
  skip_before_action :verify_authenticity_token, only: :create
end
