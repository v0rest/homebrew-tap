class Busysign < Formula
  desc "Menu-bar app that mirrors plain Busy blocks between your macOS calendars"
  homepage "https://github.com/v0rest/busysign"
  url "https://github.com/v0rest/busysign/releases/download/v0.1.0/busysign-0.1.0.tar.gz"
  sha256 "58484bad4d136b67bee9217b2c55696b6af14369c5448a14aaedee936d7a0f61"
  license "MIT"

  bottle do
    root_url "https://github.com/v0rest/homebrew-tap/releases/download/busysign-0.1.0"
    sha256 cellar: :any_skip_relocation, arm64_golden_gate: "c9264dcf15f99ad684197649719dc02192397af210b6a7772e3578c34d037f89"
    sha256 cellar: :any_skip_relocation, arm64_tahoe:       "f284dfc30cd1d4a2667210d6efd8917a0ebb20c4c3e8d6f176f98c65d360fb3c"
    sha256 cellar: :any_skip_relocation, arm64_sequoia:     "64d9af98679c64bb8ea90b856227278438fd2d64698a44f3d0ff5d9dac4405b1"
  end

  depends_on macos: :sequoia

  def install
    system "scripts/build-app.sh", "--disable-sandbox", "--output", "#{buildpath}/BusySign.app"
    prefix.install "BusySign.app"
  end

  def caveats
    <<~EOS
      BusySign is not running yet. Open it once and allow calendar access when macOS asks:
        open #{opt_prefix}/BusySign.app

      Do this again after every upgrade. Quit the old BusySign from its menu-bar icon first.
      Each build is signed ad hoc, so macOS treats the new build as a new app and asks
      for calendar access again.
    EOS
  end

  test do
    assert_equal version.to_s, shell_output("#{prefix}/BusySign.app/Contents/MacOS/BusySign --version").strip
  end
end
