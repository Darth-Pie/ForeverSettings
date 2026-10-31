# Releasing

A version tag packages the addon and uploads it. Nothing else is needed once the one-time setup below is done.

## Each release

1. Change the addon and run the tests: `cd tests && bash run_all.sh`.
2. Raise `## Version:` in `ForeverSettings.toc` and add an entry at the top of `CHANGELOG.md` (it becomes the release's changelog on Wago).
3. Commit and push to `main`.
4. Tag and push the tag:

   ```
   git tag v0.9.1
   git push origin v0.9.1
   ```

The **Release** workflow (Actions tab) builds the zip, uploads it to Wago as a stable release for Forever, and creates a GitHub release with the zip attached. A tag containing `alpha` or `beta` (for example `v0.9.2-beta1`) is uploaded to Wago as that kind of release instead.

## Trying it without releasing

Actions tab, **Release**, **Run workflow**. This packages the addon, uploads nothing, and keeps the zip as a download on the run page for 7 days.

## One-time setup

- The Wago project ID is in `ForeverSettings.toc` as `## X-Wago-ID:`.
- An API key from the Wago developer account is stored as the repository secret `WAGO_API_TOKEN` (Settings, Secrets and variables, Actions).
- The workflow packages for Forever only (`-g forever`). Remove that option once the addon has been tried on retail.
- `-u` keeps the files' Unix line endings, so the zip holds exactly the files the tests ran against (the packager's default converts them to Windows line endings).
