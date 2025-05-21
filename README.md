# napcat-linux-installer
NapCat自动化一次性安装器
## 使用
### Linux
在需要的文件夹 执行此代码 稍等片刻即可运行 任选一个 其余为镜像

```bash
curl -o napcat.sh https://github.moeyy.xyz/https://raw.githubusercontent.com/NapNeko/napcat-linux-installer/refs/heads/main/install.sh && sudo bash napcat.sh
```

```bash
curl -o napcat.sh https://jiashu.1win.eu.org/https://raw.githubusercontent.com/NapNeko/napcat-linux-installer/refs/heads/main/install.sh && sudo bash napcat.sh
```

国外服务器可使用以下命令
```bash
curl -o napcat.sh https://raw.githubusercontent.com/NapNeko/napcat-linux-installer/refs/heads/main/install.sh && sudo bash napcat.sh
```
### 关于与使用
必须在 libnapcat_launcher.so 的目录内运行

准备工作
```
Xvfb :1 -screen 0 1x1x8 +extension GLX +render > /dev/null 2>&1 &
```
启动代码(可重复执行)
```
export DISPLAY=:1
LD_PRELOAD=./libnapcat_launcher.so qq
```
