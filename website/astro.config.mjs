import { defineConfig } from 'astro/config';

// Update `site` once the Cloudflare Pages domain is final; it feeds
// canonical URLs and social preview links.
export default defineConfig({
  site: 'https://budgetai-app.pages.dev',
  output: 'static',
  trailingSlash: 'never',
  build: { format: 'file' },
  prefetch: { prefetchAll: true, defaultStrategy: 'viewport' },
  image: {
    responsiveStyles: true,
  },
});
