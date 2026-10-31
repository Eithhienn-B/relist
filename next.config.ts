import type { NextConfig } from "next";

const nextConfig: NextConfig = {
  // Listing photos go through a server action (EXIF strip + moderation): up to 4 × 6 MB.
  // shortcut: raw phone photos are uploaded; resize in the browser first if uploads feel slow.
  experimental: {
    serverActions: { bodySizeLimit: "25mb" },
    proxyClientMaxBodySize: "25mb",
  },
  turbopack: {
    rules: {
      "*.css": {
        loaders: ["@tailwindcss/turbopack"],
        as: "*.css",
      },
    },
  },
};

export default nextConfig;
