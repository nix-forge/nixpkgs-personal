{
  appName = "ChatGPT";
  sources = {
    aarch64-darwin = {
      version = "26.1027.61615";
      url = "https://persistent.oaistatic.com/codex-app-prod/ChatGPT-darwin-arm64-26.1027.61615.zip";
      hash = "sha256-oi6B/55S5/MAbGV/8gBsA0mCh2paigArv5wA+/gwfyM=";
      buildVersion = "24141";
    };
    aarch64-linux = {
      version = "26.1027.51404";
      url = "https://persistent.oaistatic.com/codex-app-prod/linux/deb/pool/main/c/chatgpt/chatgpt_26.1027.51404_arm64.deb";
      hash = "sha256-LCulzS9cE95fXZOl4WI/u2HqSzVWVx5fdDGlcPF/j+o=";
    };
    x86_64-linux = {
      version = "26.1027.51404";
      url = "https://persistent.oaistatic.com/codex-app-prod/linux/deb/pool/main/c/chatgpt/chatgpt_26.1027.51404_amd64.deb";
      hash = "sha256-RvHiLQKGmP6e2u/VhHrs4HxFCaMNNwnhBCIHGdjBKCI=";
    };
  };
}
