# Nudge Deck marketing site

Static marketing site for [nudgedeck.app](https://nudgedeck.app), deployed on Cloudflare Pages.

Layout: hero (2-column on desktop), how it works, one features mosaic (simulator screenshots), FAQ, download.

## Local preview

```bash
npx --yes serve landing
```

Or open `landing/index.html` directly in a browser.

## App Store download link

When the listing is live, set the meta tag in `index.html`:

```html
<meta name="nudgedeck:app-store-url" content="https://apps.apple.com/app/idXXXXXXXX" />
```

While empty, the App Store badge links to `#download` and shows “Coming soon”.

## App Store Connect URLs

- Privacy Policy: `https://nudgedeck.app/privacy.html`
- Terms of Service: `https://nudgedeck.app/terms.html`
- Support: `hello@nudgedeck.app`

## Cloudflare Pages

| Setting | Value |
| --- | --- |
| Project | `nudgedeck-landing` |
| GitHub repo | `jamesshah/nudge-deck` |
| Root directory | `landing` |
| Build command | *(empty)* |
| Production branch | `main` → production (`nudgedeck.app`) |
| Preview | all other branches / PRs → preview URLs |
| Path filter | `landing/*` (only landing changes trigger builds) |
| Custom domains | `nudgedeck.app`, `www.nudgedeck.app` |

Pushes to `main` that touch `landing/**` auto-deploy production. Pull requests and other branches get preview deployments with PR comments.

Manual / Direct Upload (optional):

```bash
npx wrangler pages deploy landing --project-name=nudgedeck-landing
```
