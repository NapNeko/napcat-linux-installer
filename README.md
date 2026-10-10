# napcat-linux-installer

Linux 非侵入式安装器，支持 apt / dnf / zypper，保留 QQ 原入口。

## 安装与启动

在用于保存 NapCat 配置和插件的固定目录执行：

```bash
curl -fL -o napcat-linux.sh https://raw.githubusercontent.com/NapNeko/napcat-linux-installer/main/install.sh &&
sudo bash napcat-linux.sh --github-proxy 0
bash ./launcher.sh
```

启动器会配置 Xvfb 和 QQ 路径，无需手动设置 `DISPLAY` 或 `LD_PRELOAD`。

参数及网络设置见 [Shell 文档](https://napneko.github.io/guide/boot/Shell#linux-launcher)。
