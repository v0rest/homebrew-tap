# v0rest/tap

The Homebrew tap for [BusySign](https://github.com/v0rest/busysign), a small macOS menu-bar app that keeps "Busy"
blocks in sync between the calendars you pick in macOS Calendar.

## Install

```sh
brew install v0rest/tap/busysign
```

The full name matters. Homebrew only loads formulae from third-party taps you trust, and naming the formula in full
adds the tap and trusts this one formula in one go. BusySign needs macOS 15 Sequoia or later. On a Mac with Apple
silicon Homebrew downloads a ready build. On an Intel Mac it builds BusySign from source, which needs the Xcode Command
Line Tools (`xcode-select --install`).

Then open it once and allow calendar access when macOS asks:

```sh
open "$(brew --prefix)/opt/busysign/BusySign.app"
```

Homebrew keeps the app in its own folder. To have it in /Applications as well, add a link there once - it points at
Homebrew's `opt` folder, so it keeps working after every upgrade. This needs an admin account, with a standard one
link it into ~/Applications instead (`mkdir -p ~/Applications` first if it isn't there):

```sh
ln -sfn "$(brew --prefix)/opt/busysign/BusySign.app" /Applications/BusySign.app
```

The [BusySign README](https://github.com/v0rest/busysign) explains the first run and the settings.

## Upgrade

Quit BusySign from its menu-bar icon first, then

```sh
brew upgrade busysign
```

and open it again with the `open` command above. Every build is signed ad hoc, the ready builds too, so macOS treats
the new build as a different app and asks for calendar access again - allow it.

## Uninstall

Remove the Busy blocks first, while the app is still there, with "Remove all Busy copies…" in Settings, as the
[BusySign README](https://github.com/v0rest/busysign#uninstall) describes. Then quit BusySign and run

```sh
rm -f /Applications/BusySign.app ~/Applications/BusySign.app   # the link, if you added one
brew uninstall busysign
brew untap v0rest/tap
```

## How this tap updates

The `bump` workflow picks up each new BusySign release, checks the download against the release's SHA-256 file and
writes `Formula/busysign.rb` from the template in `scripts/update-formula.sh`. It builds, tests and audits the formula
on macOS 15, 26 and 27, makes a ready build (a bottle) on each, uploads the bottles to this repo's release
`busysign-<version>`, and only then commits the formula with them. After that it installs BusySign from the tap on each
macOS as a user would and checks that the ready build was used.

The formula is generated, so a change to it belongs in the template in `scripts/update-formula.sh`. A hand edit to
`Formula/busysign.rb` alone is overwritten when `bump` publishes the next BusySign version.

Keep immutable releases off in this repo's settings - `bump` creates the release `busysign-<version>` before it uploads
the bottles, and a run repeated before its formula commit replaces them.

`bump` runs on demand and once a day. GitHub turns off the scheduled workflows of a public repo after 60 days without
activity, so after a quiet spell enable it again and start it by hand:

```sh
gh workflow enable bump.yml -R v0rest/homebrew-tap
gh workflow run bump.yml -R v0rest/homebrew-tap
```
