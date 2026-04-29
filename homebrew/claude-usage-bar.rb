cask "claude-usage-bar" do
  version "0.1.0"
  sha256 "REPLACE_WITH_SHA256_FROM_RELEASE"

  url "https://github.com/jesusalber1/claude-usage-bar/releases/download/v#{version}/ClaudeUsageBar.zip"
  name "Claude Usage Bar"
  desc "Menu bar app showing your Claude.ai usage at a glance"
  homepage "https://github.com/jesusalber1/claude-usage-bar"

  livecheck do
    url :url
    strategy :github_latest
  end

  depends_on macos: ">= :ventura"

  app "ClaudeUsageBar.app"

  postflight do
    # Strip Gatekeeper quarantine since the app is ad-hoc signed.
    system_command "/usr/bin/xattr",
                   args: ["-dr", "com.apple.quarantine", "#{appdir}/ClaudeUsageBar.app"],
                   sudo: false
  end

  zap trash: [
    "~/Library/Preferences/com.local.claudeusagebar.plist",
  ]
end
