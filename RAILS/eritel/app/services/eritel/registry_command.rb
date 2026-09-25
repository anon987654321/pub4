# frozen_string_literal: true

module Eritel
  class RegistryCommand
    class UnknownResult < StandardError; end

    def self.call(order:)
      existing = order.registry_operations.order(:id).last
      return existing unless existing.nil?

      request_id = SecureRandom.uuid

      operation = order.registry_operations.create!(
        operation: order.operation,
        state: "pending",
        request_id:
      )

      order.update!(state: "registry_pending")

      result = dispatch(order)

      operation.update!(
        state: "succeeded",
        response_code: result[:status].to_s,
        completed_at: Time.current
      )

      operation
    rescue Eritel::RegistryAdapter::UnsupportedOperation => e
      operation&.update!(
        state: "failed",
        response_code: "unsupported",
        error_code: e.class.name,
        completed_at: Time.current
      )
      order&.update!(state: "failed")
      operation
    rescue Timeout::Error, Errno::ECONNRESET, Errno::ETIMEDOUT => e
      operation&.update!(
        state: "reconciliation",
        response_code: "unknown",
        error_code: e.class.name,
        completed_at: Time.current
      )
      order&.update!(state: "reconciliation")
      operation
    end

    def self.dispatch(order)
      registry = Registry.current

      case order.operation
      when "create"
        registry.create(
          domain: order.domain.name,
          registrant: order.registrant.attributes.slice("email", "country_code")
        )
      when "renew"
        registry.renew(domain: order.domain.name, years: 1)
      when "delete"
        registry.delete(domain: order.domain.name)
      when "restore"
        raise Eritel::RegistryAdapter::UnsupportedOperation, "restore is not configured"
      end
    end

    private_class_method :dispatch
  end
end
