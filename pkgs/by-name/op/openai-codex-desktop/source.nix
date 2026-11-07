{
  appName = "ChatGPT";
  sources = {
    aarch64-darwin = {
      version = "26.1103.41825";
      url = "https://persistent.oaistatic.com/codex-app-prod/ChatGPT-darwin-arm64-26.1103.41825.zip";
      hash = "sha256-CzDOXKx4eJO/V0tUmx0yzzY/ITApNVOKzTacZo3y/R8=";
      buildVersion = "25679";
    };
    aarch64-linux = {
      version = "26.1103.32239";
      url = "https://persistent.oaistatic.com/codex-app-prod/linux/deb/pool/main/c/chatgpt/chatgpt_26.1103.32239_arm64.deb";
      hash = "sha256-mB/4FcyMnP0C6MSdds2aTmwVEgleSHwHU2wchtUqZgI=";
    };
    x86_64-linux = {
      version = "26.1103.32239";
      url = "https://persistent.oaistatic.com/codex-app-prod/linux/deb/pool/main/c/chatgpt/chatgpt_26.1103.32239_amd64.deb";
      hash = "sha256-GMEIgI6ixS+42/ktM2LSd0HjOCxYkb1K6QOptXgTZO8=";
    };
  };
}
