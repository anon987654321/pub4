# frozen_string_literal: true

module Eritel
  class RegistryCommand
    def self.call(order:)
      existing = order.registry_operations.order(:id).last
      return existing unless existing.nil?

      operation = order.registry_operations.create!(
        operation: order.operation,
        state: "pending",
        request_id: SecureRandom.uuid,
        started_at: Time.current
      )

      order.update!(state: "registry_pending")

      result = dispatch(order)

      operation.update!(
        state: "succeeded",
        response_code: result[:status].to_s.presence || "ok",
        completed_at: Time.current
      )

      complete_order(order)
      record_audit(order, operation, result, "succeeded")
      operation
    rescue Eritel::RegistryAdapter::UnsupportedOperation => e
      operation&.update!(
        state: "failed",
        response_code: "unsupported",
        error_code: e.class.name,
        completed_at: Time.current
      )
      order&.update!(state: "failed")
      record_audit(order, operation, nil, "failed", error: e.class.name)
      operation
    rescue Timeout::Error, Errno::ECONNRESET, Errno::ETIMEDOUT => e
      operation&.update!(
        state: "reconciliation",
        response_code: "unknown",
        error_code: e.class.name,
        completed_at: Time.current
      )
      order&.update!(state: "reconciliation")
      record_audit(order, operation, nil, "reconciliation", error: e.class.name)
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
        raise RegistryAdapter::UnsupportedOperation, "restore is not configured"
      end
    end

    def self.complete_order(order)
      order.update!(state: "active")

      target = order.operation == "delete" ? "deleted" : "active"
      DomainLifecycle.transition!(order.domain, to: target, actor: "registry", metadata: {
        order_id: order.id
      }) unless order.domain.state == target
    end

    def self.record_audit(order, operation, result, outcome, error: nil)
      AuditEvent.create!(
        domain: order&.domain,
        event_type: "registry_operation",
        actor: "registry",
        data: {
          order_id: order&.id,
          operation_id: operation&.id,
          outcome:,
          request_id: operation&.request_id,
          response: result&.slice(:status, :source),
          error:
        }.compact
      )
    end

    private_class_method :dispatch, :complete_order, :record_audit
  end
end
