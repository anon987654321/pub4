
## Streaming Events
Streaming emits partial text, tool calls, and completion events as the LLM generates output. Process each event sequentially.

## Exception Handling
Catch specific SDK exceptions:
- `MaxTurnsExceeded`
- `ModelBehaviorError`
- `UserError`
- `InputGuardrailTripwireTriggered`
- `OutputGuardrailTripwireTriggered`
- `AgentsException` (base)

Never swallow a `Result::Err`; propagate or log it.

## Project Structure
