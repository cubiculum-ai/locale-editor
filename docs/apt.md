# Signed APT repository

The repository publishes `locale-editor-gui` and `locale-editor-tui` for **amd64** and **arm64**. These packages target current Kali Linux and require **glibc 2.43 or later**. They are not Debian 12/13 compatibility builds.

The GUI package contains both interfaces; the terminal-only package has no GTK dependency. The editions conflict, so installing one replaces the other. Package installation does not select a locale or modify locale defaults.

## Add the repository

Download the public archive key and inspect its complete fingerprint:

```sh
curl --fail --location --output locale-editor-archive-keyring.asc \
  https://cubiculum-ai.github.io/locale-editor/apt/locale-editor-archive-keyring.asc
gpg --show-keys --fingerprint locale-editor-archive-keyring.asc
```

Expected fingerprint (also pinned in [fingerprint.txt](apt/fingerprint.txt)):

```text
EA28 F95D 0277 0287 7D25 A156 1162 D8DB 633F 745C
```

After checking the fingerprint:

```sh
sudo install -d -m 0755 /etc/apt/keyrings
sudo install -m 0644 locale-editor-archive-keyring.asc /etc/apt/keyrings/locale-editor-archive-keyring.asc
sudo tee /etc/apt/sources.list.d/locale-editor.sources >/dev/null <<'SOURCES'
Types: deb
URIs: https://cubiculum-ai.github.io/locale-editor/apt/
Suites: stable
Components: main
Architectures: amd64 arm64
Signed-By: /etc/apt/keyrings/locale-editor-archive-keyring.asc
SOURCES
sudo apt update
sudo apt install locale-editor-gui
# Or, for a headless machine:
# sudo apt install locale-editor-tui
```

APT chooses the host architecture. Use `locale-editor` for the GUI in the GUI edition and `locale-editor-tui` for terminal mode. Updates use ordinary `sudo apt update` and `sudo apt upgrade`. Selecting a system-wide locale remains a separate administrator-authenticated action in the editor.

Only this archive key is trusted for this source. Do not use `trusted=yes`, `apt-key`, or disable signature/expiry checks.

## Release maintenance

The dedicated signing key stays encrypted in a private local GnuPG home, with native pinentry/Keychain support. Only its public export and fingerprint belong in Git. The local signing configuration lives outside the checkout at `~/.config/locale-editor-release/apt-signing.json`:

```json
{"gnupgHome":"/absolute/private/gnupg-home","fingerprint":"EA28F95D027702877D25A1561162D8DB633F745C"}
```

Protect that file with mode 0600 and the GnuPG home with mode 0700. Package builds and CI do not create production signing keys. A key rotation requires an explicitly reviewed public key/fingerprint update and corresponding client keyring update.

Build all four matching `.deb` files, then prepare a new signed snapshot:

```sh
python3 Scripts/prepare-apt-release.py \
  --output .apt-work/release-v0.2.0 \
  --package dist/public/locale-editor-gui_0.2.0-2_amd64.deb \
  --package dist/public/locale-editor-tui_0.2.0-2_amd64.deb \
  --package dist/public/locale-editor-gui_0.2.0-2_arm64.deb \
  --package dist/public/locale-editor-tui_0.2.0-2_arm64.deb
```

This verifies the full package matrix and protected signing identity, signs `Release` and `InRelease`, checks the signatures and all hashes, and produces release assets under the chosen directory. It does not publish anything or install packages. Publish the reviewed source tag and those assets as a GitHub release. The Pages workflow downloads `apt-site.tar.gz` and `SHA256SUMS`, verifies them against the public key pinned in source, and deploys a complete site snapshot. Package bytes and private signing material stay out of Git history.

Metadata expires after **90 days**. Publish a fresh signed snapshot before expiry. If no package version changes, use a new dated snapshot release/tag with the same package bytes; do not overwrite an already-published `.deb` version. The Pages workflow selects the newest published release containing a signed snapshot, including such metadata-only releases. Expired metadata fails closed. Direct release downloads remain available.

`Scripts/apt-repository.py` also accepts one complete previous four-package version through `--previous-package`, for bounded retention. Indexes use SHA-256 by-hash addressing. The complete site is limited to 900 MiB. The test suite verifies signatures, complete architectures/variants, tamper rejection, version ordering, and real APT candidate/download behavior in temporary state directories.
