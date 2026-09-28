# Durable conversational task stewardship

MASTER treats a substantial conversational goal as durable work.

A fold attempt is bounded. The goal is not.

When a conversational fold reaches its turn budget without proving completion, Master::Fix::Mission keeps the original objective, current summary, attempt count and wake state under .master/mission.json. Master::Fix::TaskSteward watches that record and re-enters another bounded CoreBridge attempt when the mission is due.

The steward is deliberately smaller than the worker. It does not create a second task ledger, duplicate FixLoop, or become a second scheduler. Mission owns the objective; the steward owns continuation; CoreBridge owns one attempt.

A process restart does not erase the goal. Boot starts the steward again, it reads the durable mission, and an eligible waiting or expired fold mission resumes without the operator typing "go on".

Completion remains evidence-driven. :complete is the terminal success state. A missing human approval becomes :needs_user and blocks instead of spinning. Infrastructure or transient attempt failures are deferred using the mission's existing bounded backoff.

Set MASTER_TASK_STEWARD=0 to disable the resident steward. MASTER_TASK_POLL_SECONDS changes its maximum poll interval; the mission's own next_wake_at remains authoritative.
