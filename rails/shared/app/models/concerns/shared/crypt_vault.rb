# frozen_string_literal: true

module Shared
  module CryptVault
    extend ActiveSupport::Concern

    class_methods do
      def encrypts_column(column_name, system_key)
        define_method("#{column_name}=") do |val|
          cipher = OpenSSL::Cipher.new("AES-256-CBC").encrypt
          cipher.key = Digest::SHA256.digest(system_key)
          cipher.iv = cipher.random_iv
          send("write_attribute", column_name, Base64.encode64(cipher.update(val.to_s) + cipher.final))
        end
        define_method(column_name) do
          cipher = OpenSSL::Cipher.new("AES-256-CBC").decrypt
          cipher.key = Digest::SHA256.digest(system_key)
          cipher.update(Base64.decode64(send("read_attribute", column_name))) + cipher.final
        end
      end
    end
  end
end
