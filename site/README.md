# Wakeloop website

A static, dependency-free landing page: `index.html` plus `assets/`. There is no build step. Open `index.html` in a browser to preview it.

It is deployed with GitHub Pages at https://kaushikdas9.github.io/Wakeloop/ by `.github/workflows/pages.yml` on every push to `main` that changes `site/`. Other free ways to publish it:

## GitHub Pages (with a workflow)

1. Add `.github/workflows/pages.yml`:

   ```yaml
   name: Deploy site
   on:
     push:
       branches: [main]
       paths: ["site/**"]
     workflow_dispatch:
   permissions:
     contents: read
     pages: write
     id-token: write
   jobs:
     deploy:
       runs-on: ubuntu-latest
       environment:
         name: github-pages
         url: ${{ steps.deployment.outputs.page_url }}
       steps:
         - uses: actions/checkout@v4
         - uses: actions/upload-pages-artifact@v3
           with:
             path: site
         - id: deployment
           uses: actions/deploy-pages@v4
   ```

2. In the repository, go to **Settings > Pages** and set **Source** to **GitHub Actions**.
3. Push to `main`. The site appears at `https://kaushikdas9.github.io/Wakeloop/`.

## Cloudflare Pages

1. In the Cloudflare dashboard, go to **Workers & Pages > Create > Pages > Connect to Git** and pick this repository.
2. Leave the build command empty and set the output directory to `site`.
3. Deploy. You get a `*.pages.dev` address, and you can add your own domain later.

## If you move to your own domain

- In `index.html`, replace the canonical placeholder comment with `<link rel="canonical" href="https://YOUR-DOMAIN/">`.
- Change `og:image` and `twitter:image` to absolute URLs (`https://YOUR-DOMAIN/assets/og.jpg`) and add `og:url`. Most link previews ignore relative image paths.

## Files

- `assets/app-icon.svg`, `assets/menu-mock.svg`: copied from the repository's `assets/`.
- `assets/wakeloop-demo.mp4`, `assets/demo-poster.jpg`: the demo GIF re-encoded with ffmpeg (about 105 KB instead of 840 KB).
- `assets/og.jpg`: 1200 x 630 social preview image.
- `assets/apple-touch-icon.png`: 180 px app icon.
