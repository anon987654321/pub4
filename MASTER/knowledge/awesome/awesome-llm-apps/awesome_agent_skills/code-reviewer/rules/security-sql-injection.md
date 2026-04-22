# Direct interpolation of user‑controlled data
user_id = params[:id]
query = "SELECT * FROM users WHERE id = #{user_id}"
result = ActiveRecord::Base.connection.execute(query)
