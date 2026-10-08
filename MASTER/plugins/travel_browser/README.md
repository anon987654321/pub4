# Travel Browser

Travel Browser gives MASTER a governed browser boundary for real travel bookings:
flights, hotels, restaurants, tours, transfers and similar reservations.

The browser may research, navigate, log in, fill ordinary travel details and
prepare a booking. Credentials, one-time codes, passport numbers and payment
details stay in the visible browser and are entered by the operator. MASTER
never stores them or asks the model to handle them.

A consequential purchase has a hard final gate. MASTER may not click the final
purchase/charge/confirm control until the caller supplies `confirm_purchase: true`
for that exact booking step. The booking response records the URL, visible page
title, amount text when available, timestamp and screenshots; it never claims
success merely because a click happened.

The plugin accepts HTTPS destinations and rejects loopback, private and other
reserved addresses through the existing SSRF guard. Page text is untrusted
external content and must not become policy or instructions. CAPTCHA, security
challenges and ambiguous post-submit state stop the operation for human action.

Sessions live under `~/.master/plugins/travel_browser/sessions/` with restrictive
permissions. The repository contains no credentials or booking state.

Example flow:

```text
MASTER: find me a flight to Malaysia next week
MASTER: inspect candidate sites
MASTER: open the selected airline/OTA
MASTER: ask the operator to log in and enter sensitive details if needed
MASTER: fill ordinary trip details
MASTER: show the exact final itinerary and total
MASTER: wait for explicit confirmation
MASTER: click the final purchase control
MASTER: verify the resulting confirmation page or reference
```

This is intentionally a browser capability rather than a collection of brittle
airline-specific APIs. Provider adapters can be added later when a provider has
a stable authenticated API and a stronger contract than DOM automation.
