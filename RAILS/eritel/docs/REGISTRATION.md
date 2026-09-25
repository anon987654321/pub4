# EriTel registration workflow

The registration workflow separates local validation from external registry mutation.

## Local gate

A registration request must pass:

1. domain normalization;
2. namespace policy;
3. registrant verification;
4. participant authorization when an intermediary is used;
5. idempotency-key uniqueness.

Only then is a pending domain and order created.

## Registry command

A separate command submits the pending order to the registry adapter.

This separation means:
- payment can be completed before registry mutation;
- retry/reconciliation can operate on a durable order;
- policy failures never become registry traffic;
- a registry outage does not destroy the original request.

## Success

A successful registry create:
- marks the registry operation succeeded;
- marks the order active;
- transitions the domain to active;
- records an audit event.

## Uncertain result

A timeout or connection reset:
- marks the operation reconciliation;
- marks the order reconciliation;
- records the transport error;
- never assumes the domain was not created.

The reconciliation worker or operator must query the authoritative registry before deciding the final state.
