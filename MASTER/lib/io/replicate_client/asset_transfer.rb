# frozen_string_literal: true

module Master
  module Io
    class ReplicateClient
      # File upload/download helpers — separate from ReplicateClient's own
      # prediction/training/model-catalog API.
      module AssetTransfer
        def upload_file(path)
          mime = path.end_with?(".png") ? "image/png" : "image/jpeg"
          upload_binary(path, mime:)
        end

        def upload_zip(path)
          upload_binary(path, mime: "application/zip")
        end

        # Fetch a prediction output URL (e.g. synthesized audio) to a local path.
        def download_url(url, path)
          uri = URI(url)
          raise "refusing non-https download url: #{url}" unless uri.scheme == "https"
          raise "refusing download from untrusted host: #{uri.host}" unless uri.host.to_s.match?(ALLOWED_DOWNLOAD_HOST)

          Net::HTTP.start(uri.host, uri.port, use_ssl: true, read_timeout: 120) do |http|
            res = http.get(uri.request_uri)
            raise "download failed #{res.code}" unless res.code.to_i.between?(200, 299)

            File.binwrite(path, res.body)
          end
          path
        end
      end
    end
  end
end
