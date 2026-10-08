# frozen_string_literal: true

class Takeaway::Order
  # The order's state machine: which status may follow which, the one write that
  # moves it, and the notification and activity that write owes the customer.
  module Lifecycle
    extend ActiveSupport::Concern

    def advance_status!
      transition_to!(next_status)
    end

    def transition_to!(next_status)
      unless may_transition_to?(next_status)
        errors.add(:status, :bad_transition, from: status, to: next_status)
        return false
      end

      attrs = { status: next_status }
      # Dispatch on the same write as the status change, so an order is never
      # observable as out_for_delivery with no courier attached. A nil id is left
      # out rather than written: no free driver in range means the order still
      # leaves the kitchen, it has nobody named on it yet.
      if next_status.to_s == "out_for_delivery" && delivery_driver_id.blank?
        assigned = dispatch_driver_id
        attrs[:delivery_driver_id] = assigned if assigned
      end
      update!(attrs)
      # `user`, `restaurant.name` and `restaurant.user` are all lazy reads, and an
      # order loaded by id (controller, driver request, job) has none of them
      # preloaded. Under strict loading — on in every environment, raising outside
      # development — this raised immediately after update! had committed the new
      # status: the order advanced, the customer was never told, and the caller saw
      # a 500. See Shared::StrictSafeAssociations.
      label = I18n.t("takeaway.statuses.#{status}", default: status.to_s)
      restaurant_record = strict_safe(:restaurant)
      courier = courier_display_name
      body = I18n.t("takeaway.order_status_body", restaurant: restaurant_record&.name, status: label)
      body += " #{I18n.t("takeaway.order_status_courier", courier: courier)}" if courier
      deliver_notification(strict_safe(:user),
        title: I18n.t("takeaway.order_status_title", status: label),
        body: body,
        source: self,
        # Waiting on food is the case a push exists for.
        kind: "order")
      record_activity!("TakeawayOrderUpdated",
        actor: restaurant_record&.user,
        source_vertical: "takeaway",
        locality: restaurant_record&.[](:city),
        visibility: "private")
      true
    end

    def advanceable?
      next_status.present?
    end

    def may_transition_to?(next_status)
      TRANSITIONS.fetch(status, []).include?(next_status.to_s)
    end

    def next_status = TRANSITIONS.fetch(status, []).first

    def cancel! = transition_to!("cancelled")
    def confirm! = transition_to!("confirmed")
    def prepare! = transition_to!("preparing")
    def dispatch! = transition_to!("out_for_delivery")
    def deliver! = transition_to!("delivered")

    private

    def status_transition_allowed
      return unless will_save_change_to_status?
      previous_status = status_in_database
      return if previous_status.blank?
      return if TRANSITIONS.fetch(previous_status, []).include?(status)

      errors.add(:status, :bad_transition, from: previous_status, to: status)
    end
  end
end
