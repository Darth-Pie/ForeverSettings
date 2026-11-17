# Releasing

A version tag packages the addon and uploads it. Nothing else is needed once the one-time setup below is done.

## Each release

1. Change the addon and run the tests: `cd tests && bash run_all.sh`.
2. Raise `## Version:` in `ForeverSettings.toc` and add an entry at the top of `CHANGELOG.md` (it becomes the release's changelog on Wago and CurseForge).
3. Commit and push to `main`.
4. Tag and push the tag:

   ```
   git tag v0.9.1
   git push origin v0.9.1
   ```

The **Release** workflow (Actions tab) builds the zip, uploads it to Wago as a stable release for Forever, and creates a GitHub release with the zip attached. A tag containing `alpha` or `beta` (for example `v0.9.2-beta1`) is uploaded to Wago as that kind of release instead.

A last step uploads the same zip to CurseForge as a release for Forever (an `alpha` or `beta` tag goes up as that kind there too). It is a step of its own on purpose: the packager uploads to CurseForge first and, when that fails, skips every other upload. So a CurseForge problem turns the run red, but Wago, the GitHub release and the kept zip are already done. When that happens, upload the zip from the GitHub release by hand on the project's Files tab at CurseForge.

## Trying it without releasing

Actions tab, **Release**, **Run workflow**. This packages the addon, uploads nothing, and keeps the zip as a download on the run page for 7 days.

## One-time setup

- The Wago project ID is in `ForeverSettings.toc` as `## X-Wago-ID:`.
- An API key from the Wago developer account is stored as the repository secret `WAGO_API_TOKEN` (Settings, Secrets and variables, Actions).
- The CurseForge project ID is in `ForeverSettings.toc` as `## X-Curse-Project-ID:`. It is shown in the About Project box on the project's page.
- An API token from `curseforge.com/account/api-tokens` is stored as the repository secret `CF_API_TOKEN`. Until that secret exists, the CurseForge step does nothing.
- A new CurseForge project needs its first file uploaded by hand on the Files tab. That also sends the project to the moderators, and later uploads wait until it is approved.
- The workflow packages for Forever only (`-g forever`). Remove that option once the addon has been tried on retail.
- `-u` keeps the files' Unix line endings, so the zip holds exactly the files the tests ran against (the packager's default converts them to Windows line endings).
