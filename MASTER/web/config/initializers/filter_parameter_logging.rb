# frozen_string_literal: true

# Be sure to restart your server when you modify this file.

# Configure parameters to be partially matched (e.g. passw matches password) and filtered from the log file.
# Use this to limit dissemination of sensitive information.
# See the ActiveSupport::ParameterFilter documentation for supported notations and behaviors.
Rails.application.config.filter_parameters += [
  :passw, :email, :secret, :token, :_key, :crypt, :salt, :certificate, :otp, :ssn, :cvv, :cvc
]

# `/unlock <operator token>` and `/pair <code>` arrive as the command or message
# parameter, so the secret is the argument, not a key: the Parameters line showed
# the operator token in clear. Each is rewritten to keep the verb and drop the rest.
slash_secret = %r{\A(\s*/(?:unlock|pair)\s+)\S.*\z}m
Rails.application.config.filter_parameters << lambda do |key, value|
  next unless %w[command message].include?(key.to_s) && value.is_a?(String) && !value.frozen?

  value.sub!(slash_secret, '\1[FILTERED]')
end
