{
  appName = "ChatGPT";
  sources = {
    aarch64-darwin = {
      version = "26.1021.31345";
      url = "https://persistent.oaistatic.com/codex-app-prod/ChatGPT-darwin-arm64-26.1021.31345.zip";
      hash = "sha256-KvzVjgSEp2R5zKIxdOCFEnqdnmNGa3VznraCWl/2E/Q=";
      buildVersion = "21828";
    };
    aarch64-linux = {
      version = "26.1021.22027";
      url = "https://persistent.oaistatic.com/codex-app-prod/linux/deb/pool/main/c/chatgpt/chatgpt_26.1021.22027_arm64.deb";
      hash = "sha256-aN4exEBmhx5Bd7ocp5Pr7muiODl/E8eU5FsUlBwSYfs=";
    };
    x86_64-linux = {
      version = "26.1021.22027";
      url = "https://persistent.oaistatic.com/codex-app-prod/linux/deb/pool/main/c/chatgpt/chatgpt_26.1021.22027_amd64.deb";
      hash = "sha256-6wgxxzTxVPk/jrzw4X0RjaDep9wXN9xhoecURDdb8ZA=";
    };
  };
}
