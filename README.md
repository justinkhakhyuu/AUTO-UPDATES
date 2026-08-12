# Black Corps — simple auto-updates

## How it works (simple)

1. `updates/manifest.json` — only version numbers:
   ```json
   { "brutal": "1.0.2", "lite": "1.0.2" }
   ```

2. `payloads/brutal/` and `payloads/lite/` — actual files live here in the repo.

3. Loader downloads automatically. No GitHub Releases, no tags, no sha256 scripts.

## To publish a new version

1. Replace files in `payloads/brutal/` or `payloads/lite/`
2. Bump version in `updates/manifest.json`
3. `git add -A && git commit -m "brutal 1.0.3" && git push`

## Repo must be PUBLIC (or use github.token in loader)

GitHub → Settings → Danger zone → Change visibility → **Public**

Then the loader works with zero tokens.
