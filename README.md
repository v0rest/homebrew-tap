# v0rest/tap

The Homebrew tap for [BusySign](https://github.com/v0rest/busysign), a small macOS menu-bar app that keeps "Busy"
blocks in sync between the calendars you pick in macOS Calendar.

## Install

```sh
brew install v0rest/tap/busysign
```

The full name matters. Homebrew only loads formulae from third-party taps you trust, and naming the formula in full
adds the tap and trusts this one formula in one go. BusySign needs macOS 15 Sequoia or later and the Xcode Command Line
Tools (`xcode-select --install`), Homebrew builds it from source on your Mac.

Then open it once and allow calendar access when macOS asks:

```sh
open "$(brew --prefix)/opt/busysign/BusySign.app"
```

The [BusySign README](https://github.com/v0rest/busysign) explains the first run and the settings.

## Upgrade

Quit BusySign from its menu-bar icon first, then

```sh
brew upgrade busysign
```

and open it again with the `open` command above. Every build is signed ad hoc, so macOS treats the new build as a
different app and asks for calendar access again - allow it.

## Uninstall

Remove the Busy blocks first, while the app is still there, with "Remove all Busy copies…" in Settings, as the
[BusySign README](https://github.com/v0rest/busysign#uninstall) describes. Then quit BusySign and run

```sh
brew uninstall busysign
brew untap v0rest/tap
```

## How this tap updates

The `bump` workflow picks up each new BusySign release, checks the download against the release's SHA-256 file and
writes `Formula/busysign.rb` from the template in `scripts/update-formula.sh`. It commits the formula only after it has
been built, tested and audited on macOS 15, 26 and 27.

The formula is generated, so a change to it belongs in the template in `scripts/update-formula.sh`. A hand edit to
`Formula/busysign.rb` alone is overwritten by the next `bump` run.

`bump` runs on demand and once a day. GitHub turns off the scheduled workflows of a public repo after 60 days without
activity, so after a quiet spell enable it again and start it by hand:

```sh
gh workflow enable bump.yml -R v0rest/homebrew-tap
gh workflow run bump.yml -R v0rest/homebrew-tap
```
