# # Enqueue for asynchronous execution
# MyJob.perform_later(user.id, some_flag: true)
#
# # Execute synchronously (useful in tests or scripts)
# MyJob.perform_now(user.id, some_flag: true)
# 