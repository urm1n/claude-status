# Homebrew cask template. Publish a DMG from scripts/make-dmg.sh as a GitHub release,
# then fill in the URL and sha256 (printed by make-dmg.sh) and put this in a tap.
cask "claude-status-light" do
  version "1.0.0"
  sha256 "REPLACE_WITH_SHA256_FROM_make-dmg.sh"

  url "https://github.com/OWNER/claude-status-light/releases/download/v#{version}/ClaudeStatusLight-#{version}.dmg"
  name "Claude Status Light"
  desc "Menu bar light that shows what Claude Code is doing"
  homepage "https://github.com/OWNER/claude-status-light"

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
