#!/bin/sh

# Обновление репозиториев и установка необходимых пакетов
opkg update
opkg install kmod-inet-diag kmod-netlink-diag kmod-tun iptables-nft
opkg install sing-box -d ram

# Создание директории для sing-box
mkdir -p /etc/sing-box

# Открываем /etc/sing-box/config.json для редактирования или вставки конфигурации
echo "Введите вашу конфигурацию для sing-box (или скопируйте сюда файл /etc/sing-box/config.json):"
#cat > /etc/sing-box/config.json

# Замена содержимого /etc/rc.local
cat > /etc/rc.local <<EOF
opkg update
opkg install sing-box -d ram
exit 0
EOF

# Создание скрипта для инициализации sing-box
cat > /etc/init.d/sing-box <<'EOF'
#!/bin/sh /etc/rc.common
#
# Copyright (C) 2022 by nekohasekai <contact-sagernet@sekai.icu>
# 
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
# 
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
# 
# You should have received a copy of the GNU General Public License
# along with this program. If not, see <http://www.gnu.org/licenses/>.
#

START=99
USE_PROCD=1

#####  ONLY CHANGE THIS BLOCK  ######
PROG=/tmp/usr/bin/sing-box # Положение sing-box в ОЗУ
RES_DIR=/etc/sing-box/ # resource dir / working dir / the dir where you store ip/domain lists
CONF=./config.json   # where is the config file, it can be a relative path to $RES_DIR
#####  ONLY CHANGE THIS BLOCK  ######

start_service() {
  sleep 10 # Ожидание скачивания пакета sing-box при загрузке системы
  procd_open_instance
  procd_set_param command $PROG run -D $RES_DIR -c $CONF

  procd_set_param user root
  procd_set_param limits core="unlimited"
  procd_set_param limits nofile="1000000 1000000"
  procd_set_param stdout 1
  procd_set_param stderr 1
  procd_set_param respawn "${respawn_threshold:-3600}" "${respawn_timeout:-5}" "${respawn_retry:-5}"
  procd_close_instance
  iptables -I FORWARD -o singtun+ -j ACCEPT #Эта строка будет выдавать ошибку, если iptables-nft не установлен
  echo "sing-box is started!"
}

stop_service() {
  service_stop $PROG
  iptables -D FORWARD -o singtun+ -j ACCEPT
  echo "sing-box is stopped!"
}

reload_service() {
  stop
  sleep 5s
  echo "sing-box is restarted!"
  start
}
EOF

chmod +x /etc/init.d/sing-box

# Включаем и запускаем sing-box
/etc/init.d/sing-box enable
/etc/init.d/sing-box start

# Настройка сети и файрвола для sing-box
echo "Добавляем настройки для интерфейса proxy в /etc/config/network"
cat >> /etc/config/network <<EOF

config interface 'proxy'
  option proto 'none'
  option device 'singtun0'
EOF

echo "Добавляем настройки файрволла в /etc/config/firewall"
cat >> /etc/config/firewall <<EOF

config zone
  option name 'proxy'
  list network 'tunnel'
  option forward 'REJECT'
  option output 'ACCEPT'
  option input 'REJECT'
  option masq '1'
  option mtu_fix '1'
  option device 'singtun0'
  option family 'ipv4'

config forwarding
  option name 'lan-proxy'
  option dest 'proxy'
  option src 'lan'
  option family 'ipv4'
EOF

# Перезагружаем сеть
/etc/init.d/network restart

echo "Установка и настройка sing-box завершены."
