# frozen_string_literal: true

require "net/http"
require "json"
require "uri"

# Wolt Drive client — last-mile carrier for the kitchen's OWN orders
# (developer.wolt.com/docs/wolt-drive).
#
# Why: mrdamascy cuts Foodora out of the customer relationship, but Bergen is
# one outlet with its own couriers. Wolt Drive is the overflow lane: the
# checkout, the brand and the customer stay ours; Wolt only carries the bag.
# It is white-label-able, so it can stay invisible to the customer.
#
# The documented Drive flow has two steps, and this client mirrors both:
#   1. Availability  — POST /shipment-promises (venueful) returns whether Wolt
#      can carry the route, the fee and the ETA. Used by the checkout to show
#      "Wolt overtar" only when it is actually bookable.
#   2. Creation      — POST /deliveries books the courier; webhooks and the
#      tracking URL carry status from there (delivery_status polls while
#      no webhook receiver is wired).
#
# Foodora, by contrast, offers no white-label courier API: the Delivery Hero
# "Restaurant Integration API" only pushes orders that were PLACED on Foodora's
# marketplace into a merchant POS plugin (PGP-gated credentials, local rep,
# vendor app in the loop). It would put Foodora back in the loop and pay them a
# commission — the opposite of the mission — so it is deliberately not
# integrated here. If that ever changes, the client below is the seam to copy.
#
# MOCK BY DEFAULT (ENV["WOLT_DRIVE_MOCK"] != "0"): every call succeeds locally,
# never raises, and never touches the network — the dev/test stand-in for the
# Wolt dispatch backend.
#
# REAL MODE (WOLT_DRIVE_MOCK=0) performs the documented HTTP calls below
# (Bearer token from your Wolt Drive contact person; venue ids from the Wolt
# merchant panel) and may raise WoltDriveClient::NotAvailable when credentials
# are missing or Wolt answers with an error.
class WoltDriveClient
  # Raised for real-mode wiring gaps (missing ENV, API error).
  class NotAvailable < StandardError; end

  # Wolt Drive API root. The delivery endpoints are client-scoped:
  # POST /v1/clients/{client_id}/shipment-promises   — availability, fee, ETA
  # POST /v1/clients/{client_id}/deliveries          — create a delivery request
  # GET  /v1/clients/{client_id}/deliveries/{id}     — poll a delivery
  API_BASE = "https://api-developer.wolt.com/v1/clients"

  # Mock status lifecycle mirrors the webhook events Wolt Drive sends:
  # created → courier_assigned → picked_up → delivered.
  MOCK_STATUSES = %w[created courier_assigned picked_up delivered].freeze

  class << self
    # Request a courier for a ready delivery order. Fills
    # external_delivery_id and external_delivery_url on the order, returns a
    # Hash { id:, status:, courier:, tracking_url: }.
    #
    # Mock mode returns a fake-but-plausible response immediately (a courier
    # "Bergen Bud" is assigned) so the staff board flow works end-to-end.
    def request_delivery(order:)
      if mock_mode?
        request_mock_delivery(order)
      else
        request_real_delivery(order)
      end
    end

    # Step 1 of the documented flow — ask whether Wolt can carry this route
    # before the staff board offers the overflow button. Returns a Hash
    # { available:, fee_ore:, eta_minutes: }. Mock mode quotes a plausible
    # Bergen city-centre promise so the checkout can render it with zero
    # credentials.
    def shipment_promise(order:)
      if mock_mode?
        { available: true, fee_ore: 4900, eta_minutes: 35 }
      else
        headers = auth_headers  # validate the Bearer token before the URL
        uri = URI("#{API_BASE}/#{require_env('WOLT_DRIVE_CLIENT_ID')}/shipment-promises")
        payload = {
          pickup: pickup_location,
          dropoff: dropoff_location(order)
        }.to_json

        response = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 5, read_timeout: 10) do |http|
          http.post(uri.request_uri, payload, headers)
        end

        raise NotAvailable, "Wolt Drive quote failed: HTTP #{response.code}" unless response.is_a?(Net::HTTPSuccess)

        body = JSON.parse(response.body.to_s)
        { available: body["id"].present?,
          fee_ore: body.dig("fee", "amount", "value") || body.dig("delivery_fee", "amount", "value"),
          eta_minutes: body["duration"] && (body["duration"].to_i / 60) }
      end
    end

    # Poll a delivery's status. Mock: no-op that reports the created state.
    def delivery_status(delivery_id:)
      return { status: "created", courier: nil } if mock_mode?

      headers = auth_headers  # validate the Bearer token before the URL
      uri = URI("#{API_BASE}/#{require_env('WOLT_DRIVE_CLIENT_ID')}/deliveries/#{delivery_id}")
      response = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 5, read_timeout: 10) do |http|
        http.get(uri.request_uri, headers)
      end

      raise NotAvailable, "Wolt Drive poll failed: HTTP #{response.code}" unless response.is_a?(Net::HTTPSuccess)

      body = JSON.parse(response.body.to_s)
      { status: body["status"], courier: body.dig("courier", "name") }
    end

    def mock_mode?
      ENV["WOLT_DRIVE_MOCK"] != "0"
    end

    private

    def request_mock_delivery(order)
      delivery_id = "mock-wolt-#{order.tracking_token}"
      store_delivery!(order, id: delivery_id, url: tracking_url(delivery_id), courier: "Bergen Bud")
      { id: delivery_id, status: "courier_assigned", courier: order.courier_name,
        tracking_url: order.external_delivery_url }
    end

    def request_real_delivery(order)
      headers = auth_headers  # validate the Bearer token before the URL
      uri = URI("#{API_BASE}/#{require_env('WOLT_DRIVE_CLIENT_ID')}/deliveries")
      payload = {
        pickup: { location: pickup_location, comment: "Mr. Damascy, Solheimsgaten 60" },
        dropoff: dropoff(order),
        items: item_summary(order),
        tips: { amount: { value: order.tip_ore.to_i, currency: "NOK" } }
      }.to_json

      response = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 5, read_timeout: 10) do |http|
        http.post(uri.request_uri, payload, headers)
      end

      unless response.is_a?(Net::HTTPSuccess)
        raise NotAvailable, "Wolt Drive create failed: HTTP #{response.code}"
      end

      body = JSON.parse(response.body.to_s)
      delivery_id = body["id"] || "wolt-#{order.tracking_token}"
      store_delivery!(order, id: delivery_id, url: body.dig("tracking", "url"), courier: body.dig("courier", "name"))
      { id: delivery_id, status: body["status"], courier: order.courier_name,
        tracking_url: order.external_delivery_url }
    end

    # The booked delivery and the courier Wolt named, kept on the order for
    # the staff board.
    def store_delivery!(order, id:, url:, courier:)
      order.update!(external_delivery_id: id, external_delivery_url: url, courier_name: courier)
    end

    # Where the bag goes and who to ask for: the courier reads the address
    # with the customer's note (door code, floor) and the name they gave.
    def dropoff(order)
      { location: dropoff_location(order), comment: order.courier_comment,
        customer: { name: order.addressee, phone: order.phone } }
    end

    # --- Shared real-mode plumbing -----------------------------------------

    def auth_headers
      {
        "Content-Type" => "application/json",
        "Authorization" => "Bearer #{require_env('WOLT_DRIVE_API_TOKEN')}"
      }
    end

    def pickup_location
      # Danmarksplass, Bergen (the kitchen's corner) — real coordinates from
      # the restaurant's Google Maps listing.
      { coordinates: { latitude: 60.3757, longitude: 5.3379 }, formatted_address: "Solheimsgaten 60, 5054 Bergen" }
    end

    def dropoff_location(order)
      # Bergen city-centre anchor; a real build would geocode the postcode via
      # Kartverket/Bring's free address API and cache it on the order.
      { coordinates: { latitude: 60.3930, longitude: 5.3242 },
        formatted_address: [ order.address, order.postcode, "Bergen" ].compact.join(", ") }
    end

    def item_summary(order)
      {
        count: order.order_items.sum(&:quantity),
        description: order.order_items.map { |line| "#{line.quantity}× #{line.name}" }.join(", "),
        disclaimer: "Keep warm and flat — shawarma."
      }
    end

    def tracking_url(delivery_id)
      "https://wolt.com/en/track/#{delivery_id}"
    end

    def require_env(key)
      ENV[key].presence || raise(NotAvailable, "Missing ENV #{key} for real Wolt Drive mode")
    end
  end
end
