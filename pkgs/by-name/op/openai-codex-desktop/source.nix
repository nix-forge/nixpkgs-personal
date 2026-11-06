{
  appName = "ChatGPT";
  sources = {
    aarch64-darwin = {
      version = "26.1103.31037";
      url = "https://persistent.oaistatic.com/codex-app-prod/ChatGPT-darwin-arm64-26.1103.31037.zip";
      hash = "sha256-e60UfUBEYZJ1fb/dceJlKRRoI63ivMUrPW5lJd6BZhM=";
      buildVersion = "25241";
    };
    aarch64-linux = {
      version = "26.1103.31037";
      url = "https://persistent.oaistatic.com/codex-app-prod/linux/deb/pool/main/c/chatgpt/chatgpt_26.1103.31037_arm64.deb";
      hash = "sha256-TdCkRxLg+lgh3V+4dC8Jvq7zBtqH7EOpqyQUKGSsiVk=";
    };
    x86_64-linux = {
      version = "26.1103.31037";
      url = "https://persistent.oaistatic.com/codex-app-prod/linux/deb/pool/main/c/chatgpt/chatgpt_26.1103.31037_amd64.deb";
      hash = "sha256-Mv7YCtP4yvZm5YYAIjYelwnWSqMYz7GfVI6LRY1PZ5M=";
    };
  };
}
