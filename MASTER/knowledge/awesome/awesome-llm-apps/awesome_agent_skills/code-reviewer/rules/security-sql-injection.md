
# Vulnerable to: get_user("1 OR 1=1")
# Executes: SELECT * FROM users WHERE id = 1 OR 1=1
# Returns all users!

**Why it’s dangerous:**
- Attacker injects arbitrary SQL
- Bypasses authentication
- Extracts entire database- Simple input becomes executable code

## ✅ Correct

**Solution:** Use parameterized queries (prepared statements).

