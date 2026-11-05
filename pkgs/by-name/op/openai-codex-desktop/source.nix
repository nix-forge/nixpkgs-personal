{
  appName = "ChatGPT";
  sources = {
    aarch64-darwin = {
      version = "26.1029.70936";
      url = "https://persistent.oaistatic.com/codex-app-prod/ChatGPT-darwin-arm64-26.1029.70936.zip";
      hash = "sha256-LM/4A3LvH/Kv2ywUW3CblL1ePfzreahDnhyadYZXNzA=";
      buildVersion = "24905";
    };
    aarch64-linux = {
      version = "26.1029.61003";
      url = "https://persistent.oaistatic.com/codex-app-prod/linux/deb/pool/main/c/chatgpt/chatgpt_26.1029.61003_arm64.deb";
      hash = "sha256-Rxmt+zP+aOe+zbgWnOpZRaKX67fjqplm3nwqlFJCvCs=";
    };
    x86_64-linux = {
      version = "26.1029.61003";
      url = "https://persistent.oaistatic.com/codex-app-prod/linux/deb/pool/main/c/chatgpt/chatgpt_26.1029.61003_amd64.deb";
      hash = "sha256-86+K/sXSXCKOtvTb2c/eD+p8peS0Kv8BRaHe0nPQGy0=";
    };
  };
}
