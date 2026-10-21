# frozen_string_literal: true

# Shared registered-account email confirmation, mounted by Brgen and Amber.
get  "verify/:token" => "email_verifications#show",   as: :verify_email
post "verify/resend" => "email_verifications#create", as: :resend_verification
