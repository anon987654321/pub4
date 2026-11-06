# frozen_string_literal: true

# Be sure to restart your server when you modify this file.

# Configure parameters to be partially matched and filtered from the log file.
# Use this to limit dissemination of sensitive information.
# See the Securing Rails Applications Guide for more information:
# https://guides.rubyonrails.org/security.html#filtering-parameters
#
# Phones and one-time codes are the credentials of this app — keep both out of
# the logs alongside the usual password/secret family.
Rails.application.config.filter_parameters += [
  :passw, :email, :secret, :token, :crypt, :salt, :certificate, :otp, :cvv, :cvc, :phone
]
