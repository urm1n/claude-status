# Homebrew cask template. To offer `brew install --cask`, copy this into a tap repo
# (e.g. github.com/urm1n/homebrew-tap) and set sha256 from the release's SHA256SUMS.txt.
cask "claude-status-light" do
  version "1.0.0"
  sha256 "REPLACE_WITH_SHA256_FROM_make-dmg.sh"

  url "https://github.com/urm1n/claude-status/releases/download/v#{version}/ClaudeStatusLight-#{version}.dmg"
  name "Claude Status Light"
  desc "Menu bar light that shows what Claude Code is doing"
  homepage "https://github.com/urm1n/claude-status"

  depends_on macos: ">= :sonoma"

  app "Claude Status Light.app"

  uninstall_preflight do
    system_command "#{Dir.home}/.claude-status-light/bin/csl-hook",
                   args: ["uninstall"], must_succeed: false
  end

  zap trash: [
    "~/.claude-status-light",
    "~/Library/Preferences/com.claudestatuslight.app.plist",
  ]
end
