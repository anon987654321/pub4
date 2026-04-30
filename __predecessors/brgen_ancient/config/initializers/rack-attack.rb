class Rack::Attack

  # Spammy clients

  # Throttle requests by IP (60rpm)
  throttle("req/ip", :limit => 300, :period => 5.minutes) do |req|
    req.ip
  end

  # Prevent brute-force login attacks

  # Throttle POST requests to `users/sign_in` by IP address
  throttle("logins/ip", :limit => 5, :period => 20.seconds) do |req|
    if req.path == "users/sign_in" && req.post?
      req.ip
    end
  end

  # Throttle POST requests to `users/sign_in` by email
  throttle("logins/email", :limit => 5, :period => 20.seconds) do |req|
    if req.path == "users/sign_in" && req.post?

      # Return the email if present, otherwise nil
      req.params["email"].presence
    end
  end
end

