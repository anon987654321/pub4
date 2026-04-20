
## Example

**User Report:** "My API returns 500 errors randomly"

**Response:**

## Problem Statement
API endpoint intermittently returns 500 errors.

## EnvironmentNode.js version, database, concurrency.

## Error Analysis
Need stack trace, server logs, failing request.

## Hypotheses (Priority)

1. **Database Pool Exhaustion** – Failures align with traffic spikes.
2. **Missing Await** – Async race condition.
3. **Unhandled Rejection** – Promise lacks catch.

## Investigation Steps
1. **Add Logging**
   