# Runbook: live provider integration

A parser, fixture or mocked adapter is not evidence of a live integration.
Use a test account and the provider’s supported test environment first. Do
not place credentials, personal correspondence or customer records in public
evidence logs.

## Calendar or email

Prove one narrow read-only workflow against an operator-authorized non-Google-
Calendar provider. Record the permission scope, subject/account boundary,
freshness check, returned-item count and visible error behavior. Confirm that
no write or send endpoint is reachable through this path. Do not record message
bodies or personal contact data in the public artifact.

## External messaging

Telegram is not a target. For the operator-selected channel, verify identity
isolation, permission checks immediately before side effects, reconnect,
attachment limits, delivery receipts and handling of untrusted inbound
instructions. Distinguish “queued”, “sent”, “delivered”, “failed” and
“unknown”; do not claim delivery from a successful local enqueue.

## Advice quality

Evaluate realistic scenarios for usefulness, factuality, calibration, safety
and actionable next steps. Label every result as mocked, model-backed or
human-reviewed. Only explicitly human-reviewed evidence closes the human
review requirement. Keep private/medical or other sensitive prompts out of
public logs.

## Brgen revenue path

In the approved test environment, verify the configured path from listing to
offer/payment to entitlement, including idempotency, refund/failure handling,
moderation and abuse controls, privacy/terms, accounting/audit records and
production configuration. A sandbox stub can verify integration shape but
cannot establish production revenue readiness. Production proof requires
operator approval and a real configured end-to-end path.
