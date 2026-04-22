## Debugger Skill – Structured Incident Investigation  

### 1. User Report  
*Example:* “My API returns 500 errors randomly.”  

### 2. Problem Statement  
Summarise the issue in **one sentence**.  
*e.g.* “The `/orders` endpoint intermittently returns HTTP 500 responses.”  

### 3. Environment Capture  
Record only data the model can infer reliably.

| Item                | Details (fill in)                              |
|---------------------|-----------------------------------------------|
| **Runtime**         | Node v14, Ruby 3.2, Python 3.11, etc.         |
| **Framework**       | Express, Rails, Sinatra, FastAPI, etc.        |
| **Database**        | PostgreSQL 13, MySQL 8, MongoDB 5, etc.        |
| **Hosting**         | Docker, Kubernetes, Heroku, bare‑metal, etc. |
| **Concurrency**     | Workers = 4, threads = 8, async/event‑loop    |
| **Recent Deployments** | Version/tag, date, changed services           |
| **Relevant Config** | ENV vars, connection pools, timeouts          |

### 4. Error Evidence  
Collect artefacts that pinpoint the failure.

- **HTTP status** – e.g. `500 Internal Server Error`  
- **Response body** – if any  
- **Stack trace** – from server logs  
- **Request payload** – method, path, headers, body  
- **Timestamp** – correlate with logs/metrics  
- **Metrics** – CPU, memory, DB pool usage, latency spikes  

### 5. Hypotheses – Prioritised  

| # | Hypothesis | Rationale | Quick check |
|---|------------|-----------|-------------|
| 1 | **Database pool exhaustion** | Errors cluster during traffic spikes; pool may be undersized. | Inspect pool usage; look for “too many connections”. |
| 2 | **Missing `await` / async race** | Unawaited promises surface as 500s. | Grep for `async` functions without `await`; enable `unhandledRejection` handler. |
| 3 | **Unhandled promise rejection** | Process can crash on rejected promises. | Search logs for `UnhandledPromiseRejectionWarning`. |
| 4 | **Timeouts / circuit‑breaker trips** | Down‑stream latency propagates as 500. | Review timeout settings and circuit‑breaker state. |
| 5 | **Code‑path exception** | Null dereference or bad input on specific payloads. | Replay failing payload with verbose logging. |

### 6. Investigation Steps  

1. **Enable Structured Logging**  
   - Attach a UUID request‑ID to every request.  
   - Log start/end timestamps, status, and full stack trace.  
   - Ship logs to a searchable sink (ELK, Loki, CloudWatch).  

2. **Capture Failing Requests**  
   - Replay payloads with `curl`, `httpie`, or a load‑testing tool.  
   - Store request/response pairs together with their request‑IDs.  

3. **Monitor Resource Utilisation**  
   - Track DB pool stats, CPU, memory, and event‑loop lag during spikes.  
   - Alert on **pool > 80 %**, **CPU > 90 %**, **event‑loop lag > 100 ms**.  

4. **Detect Missing Awaits / Swallowed Errors**  
   - Static scan: `grep -R "async[^;]*\([^)]*$" .` (find async calls lacking `await`).  
   - Add a global handler: `process.on('unhandledRejection', err => console.error(err));`  

5. **Validate External Dependencies**  
   - Ping downstream APIs and caches from the same host.  
   - Add explicit timeouts, retries, and log any failures.  

6. **Review Recent Changes**  
   - `git diff` HEAD against the last known‑good tag.  
   - Highlight modifications to DB pool config, middleware, or error handling.  

7. **Apply Fixes Incrementally**  
   - Increase DB pool size or adjust connection timeout.  
   - Insert missing `await`s and wrap async calls in `try/catch`.  
   - Deploy to staging; rerun failing payloads.  

8. **Confirm Resolution**  
   - Run a sustained load test (e.g., 5 min at peak traffic).  
   - Verify **zero 500 responses** and stable resource metrics.  

### 7. Reporting Back to the User  

1. **Observations** – what was found.  
2. **Root cause** – concise statement of the defect.  
3. **Changes applied** – code or config modifications.  
4. **Verification steps** – commands or tests the user can repeat.  
5. **Preventive measures** – monitoring, alerts, and checklist items for future merges.  

---  

*Use this template for any debugging request to guarantee a thorough, reproducible, and actionable investigation.*