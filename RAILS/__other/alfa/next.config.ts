import type { NextConfig } from "next";

/*
 * Statisk eksport: `next build` produserer out/ — serveres av OpenBSD httpd
 * (OPENBSD/etc/httpd.conf), TLS via relayd/acme. Ingen API-ruter i denne appen.
 */
const nextConfig: NextConfig = {
  output: "export",
  images: { unoptimized: true },
};

export default nextConfig;
