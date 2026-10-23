{
  appName = "ChatGPT";
  sources = {
    aarch64-darwin = {
      version = "26.1016.62342";
      url = "https://persistent.oaistatic.com/codex-app-prod/ChatGPT-darwin-arm64-26.1016.62342.zip";
      hash = "sha256-s+jYC7WtT2I0IW+B5hXbvwQ72a83dOn8qL5Y7k0N8xc=";
      buildVersion = "21477";
    };
    aarch64-linux = {
      version = "26.1016.61520";
      url = "https://persistent.oaistatic.com/codex-app-prod/linux/deb/pool/main/c/chatgpt/chatgpt_26.1016.61520_arm64.deb";
      hash = "sha256-xUmDSFgfdgcQKsbyBsn4dmjM42yMfbtMAgniXNimCxE=";
    };
    x86_64-linux = {
      version = "26.1016.61520";
      url = "https://persistent.oaistatic.com/codex-app-prod/linux/deb/pool/main/c/chatgpt/chatgpt_26.1016.61520_amd64.deb";
      hash = "sha256-mt1iKRbF+jhhr9lQga934lSIwQjKnFQ+H2dWCzkNKNQ=";
    };
  };
}
