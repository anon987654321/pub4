## Security Issues (X found)

### CRITICAL: SQL Injection in `get_user()`
**File:** `api/users.py:45`
**Issue:** User input interpolated directly into SQL query
**Fix:** Use parameterized query

## Performance Issues (X found)

### HIGH: N+1 Query in `list_posts()`
**File:** `views/posts.py:23`
**Issue:** Fetching author inside loop
**Fix:** Add `.select_related('author')`
