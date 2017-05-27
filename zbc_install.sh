#!/bin/bash
# zabbix_client auto install  v0.1
#安装说明参见 https://sadsu.com/?p=170
#----------------------------------------------------------#
#                  Variables&Functions                     #
#----------------------------------------------------------#
red='\033[0;31m'
green='\033[0;32m'
yellow='\033[0;33m'
plain='\033[0m'
[[ $EUID -ne 0 ]] && echo -e "${red}Error:${plain} This script must be run as root!" && exit 1
#[[ -d "/proc/vz" ]] && echo -e "${red}Error:${plain} Your VPS is based on OpenVZ, not be supported." && exit 1
if [ -f /etc/redhat-release ]; then
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
fi

#安装程序只支持centos
[ $release != "centos" ] &&	echo -e "${red}Error:${plain} This script only support centos!" && exit 1
release_version=$(grep -o "[0-9]" /etc/redhat-release |head -n1)
#安装程序不支持centos5
[ "$release_version" -eq 5 ] && echo -e "${red}Error:${plain} This script only didn't support centos5!" && exit 1

get_char() {
    SAVEDSTTY=`stty -g`
    stty -echo
    stty cbreak
    dd if=/dev/tty bs=1 count=1 2> /dev/null
    stty -raw
    stty echo
    stty $SAVEDSTTY
}

hostip=$( ip addr | egrep -o '[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}' | egrep -v "^192\.168|^172\.1[6-9]\.|^172\.2[0-9]\.|^172\.3[0-2]\.|^10\.|^127\.|^255\.|^0\." | head -n 1 )
[ -z ${hostip} ] && hostip=$(ip route get 8.8.8.8 | awk 'NR==1 {print $NF}')



install_zabbix_client(){
echo -e "${plain} "
echo -e "${plain} "
echo -e "${plain}============================================================"
echo -e "${yellow}开始安装zabbix客户端"
echo -e "${plain}============================================================"
#安装需求配件
yum install -y gcc-c++ epel-release zip unzip screen
#安装rar
cd /tmp
wget https://fossies.org/linux/misc/zabbix-3.2.6.tar.gz
tar zxf zabbix-3.2.6.tar.gz
cd zabbix-3.2.6
./configure --prefix=/usr/local/zabbix --enable-agent
make && make install
cp misc/init.d/fedora/core/zabbix_agentd /etc/init.d
groupadd zabbix
useradd zabbix -g zabbix -s /bin/false
chkconfig --add zabbix_agentd
chkconfig zabbix_agentd on
cd /tmp
rm zabbix* -rf
}

conf_zabbix_client(){
#修改/usr/local/zabbix/etc/zabbix_agentd.conf配置项
sed -i 's/Server=127.0.0.1/Server='$server_ip'/g' /usr/local/zabbix/etc/zabbix_agentd.conf
sed -i 's/ServerActive=127.0.0.1/ServerActive='$server_ip'/g' /usr/local/zabbix/etc/zabbix_agentd.conf
sed -i 's/Hostname=Zabbix server/Hostname='$client_ip'/g' /usr/local/zabbix/etc/zabbix_agentd.conf
#修改/etc/init.d/zabbix_agentd配置项
sed -i 's/BASEDIR=\/usr\/local/BASEDIR=\/usr\/local\/zabbix/g' /etc/init.d/zabbix_agentd
}

#修改防火墙配置
config_firewall() {
    if [ "$release_version" -eq 6 ]; then
        /etc/init.d/iptables status > /dev/null 2>&1
        if [ $? -eq 0 ]; then
            iptables -L -n | grep -i 10050 > /dev/null 2>&1
            if [ $? -ne 0 ]; then
                iptables -I INPUT -m state --state NEW -m tcp -p tcp --dport 10050 -j ACCEPT
                /etc/init.d/iptables save
                /etc/init.d/iptables restart
            else
                echo -e "${green}Info:${plain} port ${green}10050${plain} already be enabled."
            fi
        else
            echo -e "${yellow}Warning:${plain} iptables looks like shutdown or not installed, please enable port 10050 manually if necessary."
        fi
    elif [ "$release_version" -eq 7 ]; then
        systemctl status firewalld > /dev/null 2>&1
        if [ $? -eq 0 ]; then
            firewall-cmd --permanent --zone=public --add-port=10050/tcp
            firewall-cmd --reload
        else
		   systemctl status iptables > /dev/null 2>&1
		   if [ $? -eq 0 ]; then
				iptables -L -n | grep -i 10050 > /dev/null 2>&1
				if [ $? -ne 0 ]; then
					iptables -I INPUT -m state --state NEW -m tcp -p tcp --dport 10050 -j ACCEPT
					/usr/libexec/iptables/iptables.init save
					service iptables restart
				fi
		   else
				echo -e "${yellow}Warning:${plain} firewalld looks like not running, try to start..."
				systemctl start firewalld
				if [ $? -eq 0 ]; then
					firewall-cmd --permanent --zone=public --add-port=10050/tcp
					firewall-cmd --reload
				else
					echo -e "${yellow}Warning:${plain} Start firewalld failed, please enable port 10050 manually if necessary."
				fi
		   fi
        fi
    fi
}

show_end(){
echo -e "========================================================================"
echo -e "=                zabbix_clent 安装完毕,已启动                          ="
echo -e "=           前往$server_ip服务器配置本节点开始监控吧              ="
echo -e "=                                                                      ="
echo -e "========================================================================"
}



echo "  请zabbix server的IP地址:"
    read -p "(默认地址: $hostip):" server_ip
    [ -z ${server_ip} ] && server_ip=$hostip
	
echo "  请zabbix client的IP地址:"
    read -p "(默认地址: $hostip):" client_ip
    [ -z ${client_ip} ] && client_ip=$hostip


clear
echo -e "===========================================================
                         程序准备安装	
     你的服务器环境变量如下：
     ${plain}zabbix server IP  : ${yellow}${server_ip} 
     ${plain}zabbix client IP  : ${yellow}${client_ip}      
${plain}==========================================================="
echo "按任意键开始安装 Ctrl+C 取消"
char=`get_char`	

install_zabbix_client
conf_zabbix_client
config_firewall
service zabbix_agentd start
show_end

