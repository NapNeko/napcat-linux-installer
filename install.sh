#!/bin/bash

# 颜色变量
MAGENTA='\033[0;1;35;95m'
RED='\033[0;1;31;91m'
YELLOW='\033[0;1;33;93m'
GREEN='\033[0;1;32;92m'
CYAN='\033[0;1;36;96m'
BLUE='\033[0;1;34;94m'
NC='\033[0m'

function log() {
    time=$(date +"%Y-%m-%d %H:%M:%S")
    message="[${time}]: $1 "
    case "$1" in
    *"失败"* | *"错误"* | *"sudo不存在"* | *"当前用户不是root用户"* | *"无法连接"*)
        echo -e "${RED}${message}${NC}"
        ;;
    *"成功"*)
        echo -e "${GREEN}${message}${NC}"
        ;;
    *"忽略"* | *"跳过"* | *"默认"* | *"警告"*)
        echo -e "${YELLOW}${message}${NC}"
        ;;
    *)
        echo -e "${BLUE}${message}${NC}"
        ;;
    esac
}

function check_privilege() {
    if [[ $EUID -eq 0 ]]; then
        log "脚本正在以root权限运行。"
        return
    fi

    if ! command -v sudo &> /dev/null; then
        if command -v apt-get &> /dev/null; then
            log "sudo不存在, 请手动安装: apt-get install -y sudo"
        elif command -v dnf &> /dev/null; then
            log "sudo不存在, 请手动安装: dnf install -y sudo"
        elif command -v pacman &> /dev/null; then
            log "sudo不存在, 请手动安装: pacman -S sudo"
        else
            log "sudo不存在, 且未检测到apt-get/dnf/pacman, 请使用当前发行版的包管理器手动安装sudo"
        fi
        exit 1
    fi

    log "非root用户运行，将在必要操作时使用sudo申请权限。"
}

function run_as_root() {
    if [[ $EUID -eq 0 ]]; then
        "$@"
    else
        sudo "$@"
    fi
}

function prompt_continue_after_failure() {
    local message="$1"
    local answer

    log "${message}"
    read -r -p "是否仍然继续? [y/N]: " answer
    case "${answer}" in
        y | Y | yes | YES | Yes)
            log "用户选择继续执行..."
            ;;
        *)
            log "用户选择终止安装"
            exit 1
            ;;
    esac
}

function run_package_command() {
    local description="$1"
    shift

    "$@"
    local status=$?
    if [ ${status} -ne 0 ]; then
        prompt_continue_after_failure "${description}失败 (退出码: ${status})"
    fi
}

function detect_package_manager() {
    if command -v apt-get &> /dev/null; then
        package_manager="apt-get"
    elif command -v dnf &> /dev/null; then
        package_manager="dnf"
    elif command -v pacman &> /dev/null; then
        package_manager="pacman"
    else
        log "高级包管理器检查失败, 目前仅支持apt-get/dnf/pacman。"
        exit 1
    fi
    log "当前高级包管理器: ${package_manager}"
}

function detect_package_installer() {
    if [ "${package_manager}" = "pacman" ] && command -v pacman &> /dev/null; then
        package_installer="pacman"
    elif command -v dpkg &> /dev/null; then
        package_installer="dpkg"
    elif command -v rpm &> /dev/null; then
        package_installer="rpm"
    elif command -v pacman &> /dev/null; then
        package_installer="pacman"
    else
        log "基础包管理器检查失败, 目前仅支持dpkg/rpm/pacman。"
        exit 1
    fi
    log "当前基础包管理器: ${package_installer}"
}

function install_dependency() {
    log "开始更新依赖..."
    detect_package_manager

    if [ "${package_manager}" = "apt-get" ]; then
        run_package_command "apt-get更新依赖" run_as_root apt-get update -y -qq
        run_package_command "apt-get安装依赖" run_as_root apt-get install -y -qq zip unzip jq curl xvfb screen xauth procps g++
    elif [ "${package_manager}" = "dnf" ]; then
        run_package_command "dnf安装epel-release" run_as_root dnf install -y epel-release
        run_package_command "dnf安装依赖" run_as_root dnf install --allowerasing -y zip unzip jq curl xorg-x11-server-Xvfb screen procps-ng gcc-c++
    elif [ "${package_manager}" = "pacman" ]; then
        log "将使用 pacman -Sy 安装依赖, 可能存在Arch Linux系部分升级风险..."
        run_package_command "pacman安装依赖" run_as_root pacman -Sy --needed --noconfirm \
            zip unzip jq curl xorg-server-xvfb screen xorg-xauth procps-ng gcc \
            fuse2 nss alsa-lib gtk3 gjs at-spi2-core libvips openjpeg2 openslide

        if command -v fusermount &> /dev/null && [ ! -u "$(command -v fusermount)" ]; then
            log "检测到 fusermount 未设置SUID, 正在尝试修复AppImage FUSE权限..."
            run_as_root chmod u+s "$(command -v fusermount)" || log "警告: fusermount SUID修复失败, AppImage可能无法启动"
        fi
    fi
    log "依赖安装成功..."
}

function network_test() {
    local timeout=10
    local status=0
    local found=0
    target_proxy=""
    log "开始网络测试: Github..."

    proxy_arr=("https://ghfast.top" "https://gh.wuliya.xin" "https://gh-proxy.com" "https://github.moeyy.xyz")
    check_url="https://raw.githubusercontent.com/NapNeko/NapCatQQ/main/package.json"

    for proxy in "${proxy_arr[@]}"; do
        log "测试代理: ${proxy}"
        status=$(curl -k -L --connect-timeout ${timeout} --max-time $((timeout*2)) -o /dev/null -s -w "%{http_code}" "${proxy}/${check_url}")
        curl_exit=$?
        if [ $curl_exit -ne 0 ]; then
            log "代理 ${proxy} 测试失败或超时 (错误码: $curl_exit)"
            continue
        fi
        if [ "${status}" = "200" ]; then
            found=1
            target_proxy="${proxy}"
            log "将使用Github代理: ${proxy}"
            break
        fi
    done

    if [ ${found} -eq 0 ]; then
        log "警告: 无法找到可用的Github代理，将尝试直连..."
        status=$(curl -k --connect-timeout ${timeout} --max-time $((timeout*2)) -o /dev/null -s -w "%{http_code}" "${check_url}")
        if [ $? -eq 0 ] && [ "${status}" = "200" ]; then
            log "直连Github成功，将不使用代理"
            target_proxy=""
        else
            log "警告: 无法连接到Github，请检查网络。将继续尝试安装，但可能会失败。"
        fi
    fi
}

function create_tmp_folder() {
    if [ -d "./napcat" ] && [ "$(ls -A ./napcat)" ]; then
        local answer
        log "文件夹已存在且不为空(./napcat)"
        read -r -p "是否覆盖napcat文件夹? [y/N]: " answer
        case "${answer}" in
            y | Y | yes | YES | Yes)
                log "用户选择覆盖napcat文件夹"
                rm -rf ./napcat
                ;;
            *)
                log "用户选择终止安装"
                exit 1
                ;;
        esac
    fi
    mkdir -p ./napcat
}

function clean() {
    # 不再清理 ./napcat 文件夹
    rm -rf ./NapCat.Shell.zip
}

function download_napcat() {
    create_tmp_folder
    default_file="NapCat.Shell.zip"
    if [ -f "${default_file}" ]; then
        log "检测到已下载NapCat安装包,跳过下载..."
    else
        log "开始下载NapCat安装包,请稍等..."
        network_test
        napcat_download_url="${target_proxy:+${target_proxy}/}https://github.com/NapNeko/NapCatQQ/releases/latest/download/NapCat.Shell.zip"
        curl -k -L -# "${napcat_download_url}" -o "${default_file}"
        if [ $? -ne 0 ]; then
            log "文件下载失败, 请检查错误。或者手动下载压缩包并放在脚本同目录下"
            clean
            exit 1
        fi
        log "${default_file} 成功下载。"
    fi

    log "正在验证 ${default_file}..."
    unzip -t "${default_file}" > /dev/null 2>&1
    if [ $? -ne 0 ]; then
        log "文件验证失败, 请检查错误。"
        clean
        exit 1
    fi

    log "正在解压 ${default_file}..."
    unzip -q -o -d ./napcat NapCat.Shell.zip
    if [ $? -ne 0 ]; then
        log "文件解压失败, 请检查错误。"
        clean
        exit 1
    fi
}

function get_system_arch() {
    local machine_arch

    machine_arch=$(uname -m 2>/dev/null)
    case "${machine_arch}" in
        x86_64 | amd64)
            system_arch="amd64"
            ;;
        aarch64 | arm64)
            system_arch="arm64"
            ;;
        *)
            log "无法识别的系统架构: ${machine_arch}, 请检查错误。"
            exit 1
            ;;
    esac
    log "当前系统架构: ${system_arch}"
}

function get_linuxqq_appimage_url() {
    local config_url="https://cdn-go.cn/qq-web/im.qq.com_new/latest/rainbow/pcConfig.json"
    local fallback_config_url="https://im.qq.com/proxy/domain/cdn-go.cn/qq-web/im.qq.com_new/latest/rainbow/pcConfig.json"
    local config_json=""

    log "正在获取QQ Linux版官方下载配置..."
    config_json=$(curl -fsSL --connect-timeout 10 --max-time 20 "${config_url}" || curl -fsSL --connect-timeout 10 --max-time 20 "${fallback_config_url}")
    if [ $? -ne 0 ] || [ -z "${config_json}" ]; then
        log "QQ Linux版官方下载配置获取失败"
        return 1
    fi

    if [ "${system_arch}" = "amd64" ]; then
        qq_download_url=$(printf "%s" "${config_json}" | jq -r '.Linux.x64DownloadUrl.appimage // empty')
    elif [ "${system_arch}" = "arm64" ]; then
        qq_download_url=$(printf "%s" "${config_json}" | jq -r '.Linux.armDownloadUrl.appimage // empty')
    else
        log "当前Arch Linux系安装方式仅支持amd64/arm64: ${system_arch}"
        return 1
    fi

    if [ -z "${qq_download_url}" ]; then
        log "QQ Linux版AppImage下载地址解析失败"
        return 1
    fi
}

function detect_qq_command() {
    if command -v qq > /dev/null 2>&1; then
        qq_command="qq"
        log "检测到QQ启动命令: ${qq_command}"
        return 0
    elif command -v linuxqq > /dev/null 2>&1; then
        qq_command="linuxqq"
        log "检测到QQ启动命令: ${qq_command}"
        return 0
    fi

    qq_command=""
    return 1
}

function install_linuxqq() {
    if detect_qq_command; then
        log "已找到QQ启动命令, 跳过LinuxQQ自动安装流程"
        return
    fi

    get_system_arch
    detect_package_installer
    log "安装LinuxQQ..."
    if [ "${package_manager}" = "pacman" ]; then
        get_linuxqq_appimage_url || exit 1
    elif [ "${system_arch}" = "amd64" ]; then
        if [ "${package_installer}" = "rpm" ]; then
            qq_download_url="https://dldir1v6.qq.com/qqfile/qq/QQNT/7516007c/linuxqq_3.2.25-45758_x86_64.rpm"
        elif [ "${package_installer}" = "dpkg" ]; then
            qq_download_url="https://dldir1v6.qq.com/qqfile/qq/QQNT/7516007c/linuxqq_3.2.25-45758_amd64.deb"
        fi
    elif [ "${system_arch}" = "arm64" ]; then
        if [ "${package_installer}" = "rpm" ]; then
            qq_download_url="https://dldir1v6.qq.com/qqfile/qq/QQNT/7516007c/linuxqq_3.2.25-45758_aarch64.rpm"
        elif [ "${package_installer}" = "dpkg" ]; then
            qq_download_url="https://dldir1v6.qq.com/qqfile/qq/QQNT/7516007c/linuxqq_3.2.25-45758_arm64.deb"
        fi
    fi

    if [ "${package_manager}" = "dnf" ]; then
        if ! [ -f "QQ.rpm" ]; then
            curl -k -L -# "${qq_download_url}" -o QQ.rpm
            if [ $? -ne 0 ]; then
                log "QQ下载失败"
                exit 1
            fi
        fi
        run_package_command "dnf安装LinuxQQ" run_as_root dnf localinstall -y ./QQ.rpm
        rm -f QQ.rpm
    elif [ "${package_manager}" = "apt-get" ]; then
        if ! [ -f "QQ.deb" ]; then
            curl -k -L -# "${qq_download_url}" -o QQ.deb
            if [ $? -ne 0 ]; then
                log "QQ下载失败"
                exit 1
            fi
        fi
        run_package_command "apt-get安装LinuxQQ" run_as_root apt-get install -f -y --allow-downgrades -qq ./QQ.deb
        run_package_command "apt-get安装libnss3" run_as_root apt-get install -y --allow-downgrades -qq libnss3
        run_package_command "apt-get安装libgbm1" run_as_root apt-get install -y --allow-downgrades -qq libgbm1
        if ! run_as_root apt-get install -y --allow-downgrades -qq libasound2 && ! run_as_root apt-get install -y --allow-downgrades -qq libasound2t64; then
            prompt_continue_after_failure "apt-get安装libasound2/libasound2t64失败"
        fi
        rm -f QQ.deb
    elif [ "${package_manager}" = "pacman" ]; then
        if ! [ -f "QQ.AppImage" ]; then
            curl -L -# "${qq_download_url}" -o QQ.AppImage
            if [ $? -ne 0 ]; then
                log "QQ下载失败"
                exit 1
            fi
        fi
        run_as_root mkdir -p /opt/QQ
        run_as_root install -m 755 QQ.AppImage /opt/QQ/QQ.AppImage
        run_as_root tee /usr/local/bin/qq > /dev/null << 'EOF'
#!/bin/bash

if [ -d "${HOME}/.config/QQ/versions" ]; then
    find "${HOME}/.config/QQ/versions" -name sharp-lib -type d -exec rm -r {} \; 2>/dev/null
    find "${HOME}/.config/QQ/versions" -name libssh2.so.1 -type f -exec rm {} \; 2>/dev/null
fi

rm -rf "${HOME}/.config/QQ/crash_files/"* 2>/dev/null

XDG_CONFIG_HOME=${XDG_CONFIG_HOME:-${HOME}/.config}
if [[ -f "${XDG_CONFIG_HOME}/qq-flags.conf" ]]; then
    mapfile -t QQ_USER_FLAGS <<<"$(grep -v '^#' "${XDG_CONFIG_HOME}/qq-flags.conf")"
fi

exec /opt/QQ/QQ.AppImage "${QQ_USER_FLAGS[@]}" "$@"
EOF
        run_as_root chmod +x /usr/local/bin/qq
        run_as_root ln -sf /usr/local/bin/qq /usr/local/bin/linuxqq
        qq_command="qq"
        rm -f QQ.AppImage
    fi
    log "LinuxQQ安装完成"
}

function create_launcher() {
    if [ -z "${qq_command}" ]; then
        detect_qq_command || {
            log "未找到QQ启动命令: qq/linuxqq"
            exit 1
        }
    fi

    # 写入启动步骤到 launcher.sh
    cat > launcher.sh << EOF
#!/bin/bash
set -e

display_num=""
for candidate in {1..99}; do
    if [ ! -e "/tmp/.X11-unix/X\${candidate}" ]; then
        display_num="\${candidate}"
        break
    fi
done

if [ -z "\${display_num}" ]; then
    echo "未找到可用的Xvfb DISPLAY" >&2
    exit 1
fi

Xvfb ":\${display_num}" -screen 0 1x1x8 +extension GLX +render > /tmp/napcat-xvfb-\${display_num}.log 2>&1 &
xvfb_pid=\$!
qq_pid=""
export DISPLAY=":\${display_num}"
trap "" SIGPIPE

terminate_qq() {
    if [ -n "\${qq_pid}" ] && kill -0 "\${qq_pid}" 2>/dev/null; then
        kill -TERM "\${qq_pid}" 2>/dev/null || true
        for _ in {1..50}; do
            if ! kill -0 "\${qq_pid}" 2>/dev/null; then
                return
            fi
            sleep 0.1
        done
        echo "QQ超时未退出，强制结束进程: \${qq_pid}" >&2
        kill -KILL "\${qq_pid}" 2>/dev/null || true
    fi
}

cleanup() {
    terminate_qq
    if [ -n "\${xvfb_pid}" ]; then
        kill "\${xvfb_pid}" 2>/dev/null || true
        wait "\${xvfb_pid}" 2>/dev/null || true
    fi
}

handle_signal() {
    terminate_qq
}

trap cleanup EXIT
trap handle_signal INT TERM

for _ in {1..50}; do
    if [ -S "/tmp/.X11-unix/X\${display_num}" ]; then
        break
    fi
    if ! kill -0 "\${xvfb_pid}" 2>/dev/null; then
        echo "Xvfb启动失败，日志: /tmp/napcat-xvfb-\${display_num}.log" >&2
        exit 1
    fi
    sleep 0.1
done

if [ ! -S "/tmp/.X11-unix/X\${display_num}" ]; then
    echo "Xvfb未在预期时间内就绪，日志: /tmp/napcat-xvfb-\${display_num}.log" >&2
    exit 1
fi

LD_PRELOAD=./libnapcat_launcher.so ${qq_command} --no-sandbox &
qq_pid=\$!
wait "\${qq_pid}"
qq_status=\$?
qq_pid=""
exit "\${qq_status}"
EOF

    chmod +x launcher.sh
}

function download_launcher_so() {
    get_system_arch
    network_test

    # 只支持 amd64/arm64 架构
    if [ "${system_arch}" != "amd64" ] && [ "${system_arch}" != "arm64" ]; then
        log "不支持的架构: ${system_arch}"
        exit 1
    fi

    cpp_url="https://raw.githubusercontent.com/NapNeko/napcat-linux-launcher/refs/heads/main/launcher.cpp"
    cpp_file="launcher.cpp"
    so_file="libnapcat_launcher.so"

    if [ -n "${target_proxy}" ]; then
        cpp_url_path="${cpp_url#https://}"
        download_url="${target_proxy}/${cpp_url_path}"
    else
        download_url="${cpp_url}"
    fi

    log "开始下载 ${cpp_file} ..."
    curl -k -L -# "${download_url}" -o "${cpp_file}"
    if [ $? -ne 0 ]; then
        log "${cpp_file} 下载失败，请检查网络或手动下载。"
        exit 1
    fi
    log "${cpp_file} 下载成功。"

    log "正在编译 ${so_file} ..."
    g++ -shared -fPIC "${cpp_file}" -o "${so_file}" -ldl
    if [ $? -ne 0 ]; then
        log "${so_file} 编译失败，请检查g++是否安装或源码是否有误。"
        exit 1
    fi
    rm -f "${cpp_file}"
    log "${so_file} 编译成功。"
}

clear
log "NapCat Shell 安装脚本"
check_privilege
install_dependency
download_napcat
install_linuxqq
download_launcher_so
clean
create_launcher

log "已写入启动脚本 launcher.sh:"
sed -n '1,200p' launcher.sh

if [[ $EUID -eq 0 ]]; then
    launcher_command="bash ./launcher.sh"
else
    launcher_command="sudo bash ./launcher.sh"
fi

log "启动命令: ${launcher_command}"
