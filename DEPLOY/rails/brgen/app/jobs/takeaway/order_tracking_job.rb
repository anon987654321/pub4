# frozen_string_literal: true
# AN622: Real-time order tracking

module Takeaway
  class OrderTrackingJob < ApplicationJob
    queue_as :critical
    limits_concurrency to: 1, key: ->(order_id, *) { "order-track-#{order_id}" }

    def perform(order_id)
      order = Order.find(order_id)
      10.times do
        lat = order.delivery_lat.to_f + rand * 0.001
        lng = order.delivery_lng.to_f + rand * 0.001
        Turbo::StreamsChannel.broadcast_replace_to(order, target: "driver-pin", partial: "takeaway/orders/driver_pin", locals: { lat: lat, lng: lng, eta: rand(5..25) })
        sleep 30
      end
    end
  end
end