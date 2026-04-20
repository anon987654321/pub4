
### Database Schema
| Table      | Columns                     |
|------------|-----------------------------|
| **sessions** | `session_id`, `user_id`, `app_name`, `created_at` |
| **state**    | `session_id`, `state_data`, `updated_at` |
| **events**   | `event_id`, `session_id`, `event_type`, `content`, `timestamp` |

### Session Lifecycle
1. **Create** – Initialize a session in the database.  
2. **Use** – Interact with the session.  
3. **Close** – End the session, persisting state.

## Implementation Steps
1. **Initialize Service**  
   