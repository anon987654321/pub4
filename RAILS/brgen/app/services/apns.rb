# frozen_string_literal: true

# Apple push for the iOS shell, whose WKWebView has no Push API.
#
# Configured only when both halves exist: the apnotic gem (APNs speaks HTTP/2
# only, and Ruby's standard library has no HTTP/2 client) and the provider key
# in credentials as `apns: { key:, key_id:, team_id:, topic: }`, where topic is
# the app's bundle id. Until then configured? is false, nothing is enqueued and
# the page never offers native notifications, so no reader is asked to allow
# something that cannot arrive.
module Apns
  # The token is gone for good: the app was deleted or the device reset.
  DEAD_TOKEN_REASONS = %w[BadDeviceToken Unregistered DeviceTokenNotForTopic].freeze

  module_function

  def credentials = Rails.application.credentials.apns || {}

  def configured?
    defined?(::Apnotic) && %i[key key_id team_id topic].all? { |name| credentials[name].present? } ? true : false
  end

  # One connection per environment and call; each token answers on its own, and
  # a dead one is removed so the next push does not ask APNs again. message is
  # { title:, body:, path:, thread: }.
  def deliver(tokens, message)
    tokens.group_by(&:environment).each do |environment, group|
      connection = connect(environment)
      group.each { |token| settle(token, connection.push(notification_for(token, message))) }
    ensure
      connection&.close
    end
  end

  def connect(environment)
    options = { auth_method: :token, cert_path: StringIO.new(credentials[:key]),
                key_id: credentials[:key_id], team_id: credentials[:team_id] }
    environment == "sandbox" ? ::Apnotic::Connection.development(options) : ::Apnotic::Connection.new(options)
  end

  def notification_for(token, message)
    ::Apnotic::Notification.new(token.token).tap do |notification|
      notification.topic = credentials[:topic]
      notification.alert = message.slice(:title, :body)
      notification.thread_id = message[:thread]
      notification.custom_payload = { path: message[:path] }
    end
  end

  def settle(token, response)
    status, reason = failure(response)
    return unless status

    if status == "410" || DEAD_TOKEN_REASONS.include?(reason)
      token.destroy
    else
      Rails.logger&.warn("[apns] #{status} #{reason}")
    end
  end

  # [status, reason] for a refused push; nil when it was accepted or timed out.
  def failure(response)
    return if response.nil? || response.ok?

    body = response.body
    [response.status, body.is_a?(Hash) ? body["reason"] : nil]
  end
end
