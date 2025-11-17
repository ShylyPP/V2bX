#!/bin/bash

red='\033[0;31m'
green='\033[0;32m'
yellow='\033[0;33m'
plain='\033[0m'

# 检查root权限
[[ $EUID -ne 0 ]] && echo -e "${red}错误：${plain}必须使用root用户运行此脚本！\n" && exit 1

# 检查系统
if [[ -f /etc/redhat-release ]]; then
    release="centos"
elif cat /etc/issue | grep -Eqi "debian"; then
    release="debian"
elif cat /etc/issue | grep -Eqi "ubuntu"; then
    release="ubuntu"
elif cat /etc/issue | grep -Eqi "centos|red hat|redhat"; then
    release="centos"
elif cat /proc/version | grep -Eqi "debian"; then
    release="debian"
elif cat /proc/version | grep -Eqi "ubuntu"; then
    release="ubuntu"
elif cat /proc/version | grep -Eqi "centos|red hat|redhat"; then
    release="centos"
else
    echo -e "${red}未检测到系统版本，请联系脚本作者！${plain}\n" && exit 1
fi

# 系统架构检测
arch=$(arch)

if [[ $arch == "x86_64" || $arch == "x64" || $arch == "amd64" ]]; then
    arch="amd64"
elif [[ $arch == "aarch64" || $arch == "arm64" ]]; then
    arch="arm64"
else
    echo -e "${red}检测架构失败，请联系脚本作者！${plain}\n" && exit 1
fi

echo "架构: ${arch}"

# 安装依赖
if [[ $release == "centos" ]]; then
    yum install wget curl tar -y
else
    apt install wget curl tar -y
fi

# V2bX配置
V2BX_VERSION="latest"
REPO_OWNER="ShylyPP"
REPO_NAME="V2bX-Private"
BRANCH="dev_new"
INSTALL_PATH="/usr/local/V2bX"
CONFIG_PATH="/etc/V2bX"
SERVICE_FILE="/etc/systemd/system/V2bX.service"

install_base() {
    if [[ $release == "centos" ]]; then
        yum install epel-release -y
        yum install wget curl unzip tar crontabs socat -y
    else
        apt update
        apt install wget curl unzip tar cron socat -y
    fi
}

download_V2bX() {
    echo -e "${green}开始下载V2bX...${plain}"
    
    # 创建临时目录
    rm -rf /tmp/V2bX
    mkdir -p /tmp/V2bX
    cd /tmp/V2bX
    
    # 尝试从 GitHub Releases 下载（如果有发布版本）
    # DOWNLOAD_LINK="https://github.com/${REPO_OWNER}/${REPO_NAME}/releases/latest/download/V2bX-linux-${arch}.tar.gz"
    # 由于是私有仓库，这里使用从源码编译的方式
    
    echo -e "${yellow}正在从源码编译V2bX...${plain}"
    
    # 安装 Go 环境（如果未安装）
    if ! command -v go &> /dev/null; then
        echo -e "${yellow}正在安装Go环境...${plain}"
        GO_VERSION="1.23.4"
        wget -q https://go.dev/dl/go${GO_VERSION}.linux-${arch}.tar.gz
        tar -C /usr/local -xzf go${GO_VERSION}.linux-${arch}.tar.gz
        export PATH=$PATH:/usr/local/go/bin
        echo 'export PATH=$PATH:/usr/local/go/bin' >> /etc/profile
    fi
    
    # 安装 Git（如果未安装）
    if ! command -v git &> /dev/null; then
        if [[ $release == "centos" ]]; then
            yum install git -y
        else
            apt install git -y
        fi
    fi
    
    # 克隆仓库并编译
    echo -e "${yellow}正在克隆仓库...${plain}"
    git clone -b ${BRANCH} https://github.com/${REPO_OWNER}/${REPO_NAME}.git V2bX-src
    cd V2bX-src
    
    echo -e "${yellow}正在编译V2bX...${plain}"
    export GOEXPERIMENT=jsonv2
    go mod download
    go build -v -o V2bX -tags "sing xray hysteria2 with_quic with_grpc with_utls with_wireguard with_acme with_gvisor" -trimpath -ldflags "-s -w"
    
    if [ $? -eq 0 ]; then
        echo -e "${green}编译成功！${plain}"
    else
        echo -e "${red}编译失败，请检查错误信息！${plain}"
        exit 1
    fi
}

install_V2bX() {
    echo -e "${green}开始安装V2bX...${plain}"
    
    # 创建安装目录
    mkdir -p ${INSTALL_PATH}
    mkdir -p ${CONFIG_PATH}
    
    # 复制二进制文件
    cp /tmp/V2bX/V2bX-src/V2bX ${INSTALL_PATH}/V2bX
    chmod +x ${INSTALL_PATH}/V2bX
    
    # 创建示例配置文件
    if [ ! -f ${CONFIG_PATH}/config.json ]; then
        cat > ${CONFIG_PATH}/config.json <<EOF
{
  "Log": {
    "Level": "error",
    "Output": ""
  },
  "Cores": [
    {
      "Type": "xray",
      "Log": {
        "Level": "error"
      },
      "OutboundConfigPath": "",
      "RouteConfigPath": ""
    }
  ],
  "Nodes": [
    {
      "Core": "xray",
      "ApiConfig": {
        "ApiHost": "https://your-panel.com",
        "ApiKey": "your-api-key",
        "NodeID": 1,
        "NodeType": "V2ray",
        "Timeout": 30,
        "RuleListPath": ""
      },
      "Options": {
        "EnableDNS": false,
        "DNSType": "UseIP",
        "EnableProxyProtocol": false,
        "EnableTFO": false,
        "EnableREALITY": false,
        "REALITYConfigs": {
          "Show": true
        }
      }
    }
  ]
}
EOF
        echo -e "${yellow}已创建配置文件模板: ${CONFIG_PATH}/config.json${plain}"
        echo -e "${yellow}请编辑配置文件后再启动服务！${plain}"
    fi
    
    # 清理临时文件
    rm -rf /tmp/V2bX
}

create_service() {
    echo -e "${green}创建systemd服务...${plain}"
    
    cat > ${SERVICE_FILE} <<EOF
[Unit]
Description=V2bX Service
Documentation=https://github.com/${REPO_OWNER}/${REPO_NAME}
After=network.target nss-lookup.target

[Service]
Type=simple
User=root
ExecStart=${INSTALL_PATH}/V2bX server --config ${CONFIG_PATH}/config.json
Restart=on-failure
RestartSec=10
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOF
    
    systemctl daemon-reload
    systemctl enable V2bX
    echo -e "${green}systemd服务创建完成${plain}"
}

show_usage() {
    echo -e "${green}V2bX 管理脚本使用方法: ${plain}"
    echo -e "-----------------------------"
    echo -e "启动服务: ${green}systemctl start V2bX${plain}"
    echo -e "停止服务: ${green}systemctl stop V2bX${plain}"
    echo -e "重启服务: ${green}systemctl restart V2bX${plain}"
    echo -e "查看状态: ${green}systemctl status V2bX${plain}"
    echo -e "查看日志: ${green}journalctl -u V2bX -f${plain}"
    echo -e "编辑配置: ${green}nano ${CONFIG_PATH}/config.json${plain}"
    echo -e "-----------------------------"
    echo -e "${yellow}配置文件位置: ${CONFIG_PATH}/config.json${plain}"
    echo -e "${yellow}程序安装位置: ${INSTALL_PATH}/V2bX${plain}"
}

main() {
    echo -e "${green}========================================${plain}"
    echo -e "${green}      V2bX 一键安装脚本${plain}"
    echo -e "${green}      作者: ${REPO_OWNER}${plain}"
    echo -e "${green}========================================${plain}"
    echo ""
    
    install_base
    download_V2bX
    install_V2bX
    create_service
    
    echo ""
    echo -e "${green}========================================${plain}"
    echo -e "${green}      V2bX 安装完成！${plain}"
    echo -e "${green}========================================${plain}"
    echo ""
    show_usage
    echo ""
    echo -e "${yellow}注意: 请先编辑配置文件 ${CONFIG_PATH}/config.json，然后使用 systemctl start V2bX 启动服务${plain}"
}

# 如果以参数方式运行
if [ $# -gt 0 ]; then
    case $1 in
        uninstall)
            systemctl stop V2bX
            systemctl disable V2bX
            rm -rf ${INSTALL_PATH}
            rm -rf ${CONFIG_PATH}
            rm -f ${SERVICE_FILE}
            systemctl daemon-reload
            echo -e "${green}V2bX 已卸载${plain}"
            ;;
        update)
            systemctl stop V2bX
            download_V2bX
            cp /tmp/V2bX/V2bX-src/V2bX ${INSTALL_PATH}/V2bX
            chmod +x ${INSTALL_PATH}/V2bX
            rm -rf /tmp/V2bX
            systemctl start V2bX
            echo -e "${green}V2bX 已更新${plain}"
            ;;
        *)
            echo -e "${red}未知参数: $1${plain}"
            echo -e "用法: $0 [uninstall|update]"
            ;;
    esac
else
    main
fi
