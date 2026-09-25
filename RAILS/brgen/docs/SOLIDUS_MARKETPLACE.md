# Brgen marketplace commerce

BRGEN keeps `Marketplace::*` as the public seller and order domain. Solidus is an optional commerce kernel for catalog, cart, checkout, fulfillment, and merchant operations; it is staged behind `SOLIDUS_MARKETPLACE=1` rather than replacing the marketplace domain in place.

Solidus's current marketplace offering covers capabilities such as mixed carts, split shipments, merchant storefronts, merchant dashboards, permissions, flexible fulfillment, and managed payouts. BRGEN therefore does not install the legacy `solidus_marketplace` extension.

## Responsibilities

`Marketplace::Listing`, `Marketplace::Store`, `Marketplace::Order`, seller policy, buyer–seller messaging, local geography, offers, questions, returns, and marketplace-specific lifecycle remain BRGEN-owned.

Solidus can provide the commerce kernel around product, variant, taxon, cart, checkout, shipment, and merchant operations once the database and cutover are staged.

Dintero owns marketplace money movement. A seller payout destination must be approved and `ACTIVE` before the seller slice is sent in an inline split. BRGEN persists the exact split contract on each local order and reuses it for capture and refund, so later configuration changes cannot silently rewrite a historical transaction. Capture is a separate transition from authorization, and BRGEN does not mark an order paid merely because a browser returned from checkout.

## Dintero

Dintero's Shopping API creates payment sessions for a Shopping order. The integration therefore keeps a local `dintero_order_id`, `dintero_session_id`, and `dintero_transaction_id` rather than treating a local order id as a Dintero resource.

Dintero hook delivery has its own event-delivery identity. BRGEN verifies the raw request body before JSON parsing, stores `event-delivery` for replay handling, and keeps the signed session callback separate from the webhook route.

The checkout adapter is explicitly gated by `DINTERO_CHECKOUT_ENABLED=1`. A credentialed but unverified integration therefore cannot present a payment button before the Shopping API payload has been exercised in Dintero test mode. Dintero capture and refund confirmation remain webhook-authoritative.

## Staging

1. Use a non-production host and a database supported by the Solidus deployment being evaluated.
2. Set `SOLIDUS_MARKETPLACE=1` and run the Solidus installer only on that staging host.
3. Verify the Dintero Shopping draft-order and session payload against the current test account before setting `DINTERO_CHECKOUT_ENABLED=1`.
4. Register the Dintero hook subscription against the HTTPS route configured in `DINTERO_HOOK_URL`.
5. Exercise authorization, capture, refund, duplicate delivery, seller approval, and settlement events before any production cutover.

The 1 GB OpenBSD host remains the wrong place to perform the Solidus install. The native BRGEN marketplace keeps serving the public surface until a staged cutover is deliberate.
