   # Bad: N + 1
   items.each do |item|
     user = User.find(item.user_id)   # separate query for every item
   end

   # Good: one query using IN
   user_ids = items.map(&:user_id).uniq
   users    = User.where(id: user_ids).index_by(&:id)

   items.each do |item|
     user = users[item.user_id]       # no extra DB round‑trip
   end
   