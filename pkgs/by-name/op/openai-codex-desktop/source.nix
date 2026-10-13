{
  appName = "ChatGPT";
  sources = {
    aarch64-darwin = {
      version = "26.1007.41230";
      url = "https://persistent.oaistatic.com/codex-app-prod/ChatGPT-darwin-arm64-26.1007.41230.zip";
      hash = "sha256-xUK565d6L01lmKlR43de3RKUB+6ckmROFrMVOBbz9Ws=";
      buildVersion = "20324";
    };
    aarch64-linux = {
      version = "26.1007.21434";
      url = "https://persistent.oaistatic.com/codex-app-prod/linux/deb/pool/main/c/chatgpt/chatgpt_26.1007.21434_arm64.deb";
      hash = "sha256-Vfrh4/sdYGmpBiDp5wc33Pi/IlVgTRV+KCzGdIobr0k=";
    };
    x86_64-linux = {
      version = "26.1007.21434";
      url = "https://persistent.oaistatic.com/codex-app-prod/linux/deb/pool/main/c/chatgpt/chatgpt_26.1007.21434_amd64.deb";
      hash = "sha256-J2tTQcPXSyYdOtUhBvf6ft3gaEHkdn/ipAy1QJmx8+0=";
    };
  };
}
