#!/bin/bash
set -e

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

function check_root() {
    if [[ $EUID -ne 0 ]]; then
        log "错误: 此脚本需要以 root 权限运行。"
        log "请尝试使用 'sudo bash ${0}' 或切换到 root 用户后运行。"
        exit 1
    fi
    log "脚本正在以 root 权限运行。"
}

function detect_package_manager() {
    if command -v apt-get &> /dev/null; then
        package_manager="apt-get"
    elif command -v dnf &> /dev/null; then
        package_manager="dnf"
    elif command -v zypper &> /dev/null; then
        package_manager="zypper"
    else
        log "高级包管理器检查失败, 目前仅支持apt-get/dnf/zypper。"
        exit 1
    fi
    log "当前高级包管理器: ${package_manager}"
}

function detect_package_installer() {
    if command -v dpkg &> /dev/null; then
        package_installer="dpkg"
    elif command -v rpm &> /dev/null; then
        package_installer="rpm"
    else
        log "基础包管理器检查失败, 目前仅支持dpkg/rpm。"
        exit 1
    fi
    log "当前基础包管理器: ${package_installer}"
}

function install_dependency() {
    log "开始更新依赖..."
    detect_package_manager

    if [ "${package_manager}" = "apt-get" ]; then
        apt-get update -y -qq
        apt-get install -y -qq zip unzip jq curl xvfb screen xauth procps g++
    elif [ "${package_manager}" = "dnf" ]; then
        . /etc/os-release
        if [[ " ${ID} ${ID_LIKE} " == *" rhel "* || "${ID}" = "centos" ]]; then
            dnf install -y epel-release
        fi
        dnf install -y zip unzip jq curl xorg-x11-server-Xvfb xorg-x11-xauth screen procps-ng gcc-c++ krb5-libs
    elif [ "${package_manager}" = "zypper" ]; then
        zypper --non-interactive install zip unzip jq curl xvfb-run xauth screen procps gcc-c++ krb5 cpio \
            mozilla-nss mozilla-nspr libgtk-3-0 libgbm1 libasound2 libXtst6 libXss1 libnotify4 \
            libsecret-1-0 libuuid1 libxkbcommon0 libdrm2 libX11-xcb1 libcups2 xdg-utils
    fi
    log "依赖安装成功..."
}

function curl_download() {
    local source="$1" destination="$2" partial status
    partial=$(mktemp "${destination}.XXXXXX") || return 1
    if curl -fL --connect-timeout "${NAPCAT_CONNECT_TIMEOUT:-20}" \
        --max-time "${NAPCAT_DOWNLOAD_TIMEOUT:-1800}" \
        --proto '=http,https' --proto-redir '=http,https' "$source" -o "$partial"; then
        mv -- "$partial" "$destination"
    else
        status=$?
        rm -f -- "$partial"
        return "$status"
    fi
}

function network_test() {
    if [ -n "${network_selected:-}" ]; then return 0; fi
    local setting="${github_proxy_arg:-auto}"
    target_proxy=""
    case "$setting" in
        0) network_selected=1; return 0 ;;
        http://*|https://*) target_proxy="${setting%/}"; network_selected=1; return 0 ;;
        auto) ;;
        *) log "错误: --github-proxy 需要 0、auto 或 HTTP(S) URL。"; return 1 ;;
    esac
    local proxy probe_file
    local proxies=("" "https://ghfast.top" "https://ghproxy.net" "https://gh-proxy.com" "https://github.dpik.top")
    probe_file=$(mktemp)
    for proxy in "${proxies[@]}"; do
        if curl -fLsS --connect-timeout 3 --max-time 5 --max-filesize 65536 \
            "${proxy:+${proxy}/}https://raw.githubusercontent.com/NapNeko/NapCatQQ/main/package.json" \
            -o "$probe_file" &&
            jq -e '.name == "napcat"' "$probe_file" >/dev/null 2>&1; then
            target_proxy="$proxy"
            network_selected=1
            rm -f -- "$probe_file"
            log "GitHub 下载线路: ${target_proxy:-直连}"
            return 0
        fi
    done
    rm -f -- "$probe_file"
    log "错误: 没有可用的 GitHub 下载线路，请指定代理或提供本地安装包。"
    return 1
}

function create_tmp_folder() {
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
        curl_download "${napcat_download_url}" "${default_file}"
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
    unzip -q -o -d ./napcat NapCat.Shell.zip -x 'config/*' 'plugins/*'
    unzip -q -n -d ./napcat NapCat.Shell.zip
    if [ $? -ne 0 ]; then
        log "文件解压失败, 请检查错误。"
        clean
        exit 1
    fi
}

function get_system_arch() {
    system_arch=$(arch | sed s/aarch64/arm64/ | sed s/x86_64/amd64/)
    if [[ "${system_arch}" != "amd64" && "${system_arch}" != "arm64" ]]; then
        log "不支持的系统架构: ${system_arch}，仅支持 amd64/arm64。"
        exit 1
    fi
    log "当前系统架构: ${system_arch}"
}

function download_qq() {
    local out="$1"
    log "QQ下载链接: ${qq_download_url}"
    if ! curl_download "${qq_download_url}" "${out}"; then
        rm -f "${out}"
        log "QQ下载失败"
        exit 1
    fi
}

function install_linuxqq() {
    get_system_arch
    detect_package_installer
    qq_install_dir=/opt/QQ
    if [ "${package_manager}" = "zypper" ]; then qq_install_dir=/opt/napcat-qq; fi
    qq_executable="$qq_install_dir/qq"
    log "安装LinuxQQ..."
    if [ -f "$qq_install_dir/resources/app/package.json" ] && jq -e '.buildVersion | tonumber >= 53644' "$qq_install_dir/resources/app/package.json" >/dev/null; then
        log "已安装的 LinuxQQ 版本满足要求，跳过 QQ 安装。"
        return
    fi
    if [ "${system_arch}" = "amd64" ]; then
        if [ "${package_installer}" = "rpm" ]; then
            qq_file="linuxqq_3.2.34-53644_x86_64.rpm"
        elif [ "${package_installer}" = "dpkg" ]; then
            qq_file="linuxqq_3.2.34-53644_amd64.deb"
        fi
    elif [ "${system_arch}" = "arm64" ]; then
        if [ "${package_installer}" = "rpm" ]; then
            qq_file="linuxqq_3.2.34-53644_aarch64.rpm"
        elif [ "${package_installer}" = "dpkg" ]; then
            qq_file="linuxqq_3.2.34-53644_arm64.deb"
        fi
    fi
    qq_download_url="https://qqdl.gtimg.cn/qqfile/QQNT/9.9.36/beta/9ee04bef/${qq_file}"

    if [ "${package_manager}" = "dnf" ]; then
        if ! [ -f "QQ.rpm" ]; then
            download_qq QQ.rpm
        fi
        dnf install -y ./QQ.rpm
        rm -f QQ.rpm
    elif [ "${package_manager}" = "zypper" ]; then
        if ! [ -f "QQ.rpm" ]; then
            download_qq QQ.rpm
        fi
        install_suse_qq ./QQ.rpm
        rm -f QQ.rpm
    elif [ "${package_manager}" = "apt-get" ]; then
        if ! [ -f "QQ.deb" ]; then
            download_qq QQ.deb
        fi
        apt-get install -f -y --allow-downgrades -qq ./QQ.deb
        apt-get install -y --allow-downgrades -qq libnss3
        apt-get install -y --allow-downgrades -qq libgbm1
        if apt-cache show libasound2t64 >/dev/null 2>&1; then
            apt-get install -y -qq libasound2t64
        else
            apt-get install -y -qq libasound2
        fi
        apt-get install -y -qq libgssapi-krb5-2
        rm -f QQ.deb
    fi
    log "LinuxQQ安装完成"
}

function install_suse_qq() (
    set -e -o pipefail
    local archive staging dependency_report
    archive=$(realpath -- "$1")
    staging=$(mktemp -d /opt/.napcat-qq.XXXXXX)
    trap 'rm -rf -- "$staging"' EXIT
    rpm2cpio "$archive" | (cd "$staging" && cpio -id --quiet './opt/QQ/*')
    test -x "$staging/opt/QQ/qq"
    jq -e '.buildVersion | tonumber >= 53644' "$staging/opt/QQ/resources/app/package.json" >/dev/null
    dependency_report=$(ldd "$staging/opt/QQ/qq" "$staging/opt/QQ/resources/app/wrapper.node")
    if grep -F 'not found' <<< "$dependency_report"; then
        log "错误: QQ 运行库不完整，请安装缺少的系统依赖。"
        exit 1
    fi
    if [ -e "$qq_install_dir" ]; then
        mv -- "$qq_install_dir" "$staging/previous"
    fi
    if ! mv -- "$staging/opt/QQ" "$qq_install_dir"; then
        if [ -d "$staging/previous" ]; then
            if ! mv -- "$staging/previous" "$qq_install_dir"; then
                trap - EXIT
                log "错误: 旧 QQ 保留在 $staging/previous，请手动恢复。"
            fi
        fi
        exit 1
    fi
    log "openSUSE 的 QQ 安装在 $qq_install_dir，系统依赖由 zypper 管理。"
)

function download_launcher_so() {
    get_system_arch
    # 只支持 amd64/arm64 架构
    if [ "${system_arch}" != "amd64" ] && [ "${system_arch}" != "arm64" ]; then
        log "不支持的架构: ${system_arch}"
        exit 1
    fi

    cpp_url="https://raw.githubusercontent.com/NapNeko/napcat-linux-launcher/refs/heads/main/launcher.cpp"
    cpp_file="launcher.cpp"
    so_file="libnapcat_launcher.so"

    download_url="${target_proxy:+${target_proxy}/}${cpp_url}"

    log "开始下载 ${cpp_file} ..."
    if [ -n "${launcher_source:-}" ]; then
        cp -- "$launcher_source" "$cpp_file"
    else
        network_test
        download_url="${target_proxy:+${target_proxy}/}${cpp_url}"
        curl_download "$download_url" "$cpp_file"
    fi
    if [ $? -ne 0 ]; then
        log "${cpp_file} 下载失败，请检查网络或手动下载。"
        exit 1
    fi
    log "${cpp_file} 下载成功。"

    log "正在编译 ${so_file} ..."
    g++ -shared -fPIC "${cpp_file}" -o "${so_file}.new" -ldl
    if [ $? -ne 0 ]; then
        log "${so_file} 编译失败，请检查g++是否安装或源码是否有误。"
        exit 1
    fi
    mv -- "${so_file}.new" "${so_file}"
    log "${so_file} 编译成功。"
}

while [ $# -gt 0 ]; do
    case "$1" in
        --github-proxy|--launcher-source)
            if [ $# -lt 2 ] || [[ "$2" == --* ]]; then
                echo "参数 $1 缺少值。" >&2
                exit 1
            fi
            if [ "$1" = --github-proxy ]; then github_proxy_arg="$2"; else launcher_source="$2"; fi
            shift 2
            ;;
        --skip-deps) skip_dependencies=1; shift ;;
        --help|-h)
            echo "用法: bash install.sh [--github-proxy 0|auto|URL] [--launcher-source 本地launcher.cpp] [--skip-deps]"
            exit 0
            ;;
        *) echo "未知参数: $1" >&2; exit 1 ;;
    esac
done

if [ -t 1 ]; then clear; fi
log "NapCat Shell 安装脚本"
check_root
if [ -z "${skip_dependencies:-}" ]; then install_dependency; else detect_package_manager; fi
download_napcat
install_linuxqq
download_launcher_so
clean

# 写入启动步骤到 launcher.sh
cat << 'EOF' > launcher.sh
#!/bin/bash
cd -- "$(dirname -- "${BASH_SOURCE[0]}")" || exit 1
trap "" SIGPIPE
EOF
printf 'exec xvfb-run -a env LD_PRELOAD=./libnapcat_launcher.so %q --no-sandbox "$@"\n' "$qq_executable" >> launcher.sh

chmod +x launcher.sh

log "启动步骤:"
log "运行 bash ./launcher.sh 启动 NapCat Shell，可传入 -q QQ号码快速登录。"
