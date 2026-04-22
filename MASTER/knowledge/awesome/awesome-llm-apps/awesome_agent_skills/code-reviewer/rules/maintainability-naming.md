## ✅ Naming Guidelines for the Master Codebase

### 1. Identifier style
- **Classes / Modules** – `PascalCase`, singular, match file name exactly.  
  - `Master::Tools::ReadFile` → `lib/master/tools/read_file.rb`  
  - `Master::Scan::Rules::LongMethodRule` → `lib/master/scan/rules/long_method_rule.rb`  
- **Methods / Variables** – `snake_case`. Use a verb for actions, a noun for data.  
  - `fetch_user`, `calculate_total`, `scan_file`, `apply_diff`  
- **Constants** – `SCREAMING_SNAKE_CASE`. Upper‑case only for immutable values.  
  - `MAX_RETRIES`, `DEFAULT_MODEL`, `SCAN_TIMEOUT`

### 2. Brevity with clarity
- Prefer `order` over `order_object`.  
- Omit qualifiers that add no domain meaning (`temp_`, `raw_`).

### 3. Consistency
- Use one term per concept (`client` vs `customer`).  
- Follow established patterns:  
  - Service objects end with `_service.rb` (`payment_service.rb`).  
  - Scan rules live under `Master::Scan::Rules::*Rule`.  
  - Tools live under `Master::Tools::*`.

### 4. Domain‑driven naming
- Mirror business language directly: `subscription_plan`, `payment_gateway`, `user_session`.  
- Reuse domain‑specific terms verbatim to aid domain experts and reviewers.

### 5. Remove noise
- Drop generic suffixes (`object`, `entity`, `manager`) when type is obvious.  
  - `UserRepository` instead of `UserObjectRepository`.

### 6. Data vs behavior
- **Data structures** – nouns (`Master::RingBuffer`, `Master::Pipeline`).  
- **Behaviour** – verbs (`push_item`, `pop_item`, `run_pipeline`, `stop_pipeline`).

### 7. Boolean predicates
- End with `?` and start with a clear predicate:  
  - `active?`, `admin?`, `has_errors?`, `ready_for_review?`

### 8. Parameter naming
- Name arguments after their purpose: `user_id` not just `id`.  
- Callbacks end with `_callback`: `before_save_callback`, `after_execute_callback`.

### 9. File ↔ constant mapping
- Path must reflect the fully‑qualified constant:  
  - `app/models/user.rb` → `User`  
  - `lib/master/tools/read_file.rb` → `Master::Tools::ReadFile`  
  - `lib/master/scan/rules/long_method_rule.rb` → `Master::Scan::Rules::LongMethodRule`

### 10. Automated enforcement
- Run `rubocop -A` in every CI pipeline.  
- Use `Master::Tools::ApplyDiff` to apply bulk rename diffs produced by RuboCop or IDE inspections.

---

**Result:** Uniform, domain‑aligned naming reduces cognitive load, improves readability, and lets static analysis flag violations early.