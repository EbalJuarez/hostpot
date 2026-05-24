#!/bin/bash

# Script para levantar servidor hotspot WifiGEY
# Servicios: hostapd, dnsmasq, openNDS, nginx, php-fpm, iptables

set -e

WIFI_IF="wlxe865d4121230"
WAN_IF="enp0s3"
WIFI_IP="192.168.200.1/24"
PHP_SERVICE="php8.5-fpm"

echo "======================================"
echo " Levantando servidor Hotspot WifiGEY"
echo "======================================"

echo "[1/9] Verificando interfaz WiFi USB..."

if ! ip link show "$WIFI_IF" > /dev/null 2>&1; then
    echo "ERROR: No se encontró la interfaz WiFi: $WIFI_IF"
    echo "Revisa en VirtualBox: Dispositivos → USB → selecciona el adaptador WiFi"
    echo "Interfaces actuales:"
    ip -br a
    exit 1
fi

echo "Interfaz WiFi encontrada: $WIFI_IF"

echo "[2/9] Configurando IP del WiFi..."

sudo ip link set "$WIFI_IF" up
sudo ip addr flush dev "$WIFI_IF"
sudo ip addr add "$WIFI_IP" dev "$WIFI_IF"

echo "IP asignada a $WIFI_IF: $WIFI_IP"

echo "[3/9] Activando IP forwarding..."

sudo sysctl -w net.ipv4.ip_forward=1 > /dev/null

echo "[4/9] Limpiando reglas duplicadas básicas..."

# Evita duplicar reglas en cada ejecución.
sudo iptables -t nat -D POSTROUTING -o "$WAN_IF" -j MASQUERADE 2>/dev/null || true
sudo iptables -D FORWARD -i "$WIFI_IF" -o "$WAN_IF" -j ACCEPT 2>/dev/null || true
sudo iptables -D FORWARD -i "$WAN_IF" -o "$WIFI_IF" -m state --state RELATED,ESTABLISHED -j ACCEPT 2>/dev/null || true

sudo iptables -D INPUT -i "$WIFI_IF" -p tcp --dport 2080 -j ACCEPT 2>/dev/null || true
sudo iptables -D INPUT -i "$WIFI_IF" -p tcp --dport 2050 -j ACCEPT 2>/dev/null || true
sudo iptables -D INPUT -i "$WIFI_IF" -p tcp --dport 80 -j ACCEPT 2>/dev/null || true
sudo iptables -D INPUT -i "$WIFI_IF" -p udp --dport 53 -j ACCEPT 2>/dev/null || true
sudo iptables -D INPUT -i "$WIFI_IF" -p tcp --dport 53 -j ACCEPT 2>/dev/null || true
sudo iptables -D INPUT -i "$WIFI_IF" -p udp --dport 67 -j ACCEPT 2>/dev/null || true

echo "[5/9] Aplicando reglas NAT y permisos locales..."

sudo iptables -t nat -A POSTROUTING -o "$WAN_IF" -j MASQUERADE
sudo iptables -A FORWARD -i "$WIFI_IF" -o "$WAN_IF" -j ACCEPT
sudo iptables -A FORWARD -i "$WAN_IF" -o "$WIFI_IF" -m state --state RELATED,ESTABLISHED -j ACCEPT

sudo iptables -I INPUT -i "$WIFI_IF" -p tcp --dport 2080 -j ACCEPT
sudo iptables -I INPUT -i "$WIFI_IF" -p tcp --dport 2050 -j ACCEPT
sudo iptables -I INPUT -i "$WIFI_IF" -p tcp --dport 80 -j ACCEPT
sudo iptables -I INPUT -i "$WIFI_IF" -p udp --dport 53 -j ACCEPT
sudo iptables -I INPUT -i "$WIFI_IF" -p tcp --dport 53 -j ACCEPT
sudo iptables -I INPUT -i "$WIFI_IF" -p udp --dport 67 -j ACCEPT

echo "[6/9] Reiniciando servicios..."

sudo systemctl restart hostapd
sleep 2

sudo systemctl restart dnsmasq
sleep 2

sudo systemctl restart nginx
sleep 1

sudo systemctl restart "$PHP_SERVICE"
sleep 1

sudo systemctl restart opennds
sleep 5

echo "[7/9] Verificando servicios..."

SERVICES=("hostapd" "dnsmasq" "nginx" "$PHP_SERVICE" "opennds")

for SERVICE in "${SERVICES[@]}"; do
    if systemctl is-active --quiet "$SERVICE"; then
        echo "OK: $SERVICE activo"
    else
        echo "ERROR: $SERVICE no está activo"
        sudo systemctl status "$SERVICE" --no-pager
        exit 1
    fi
done

echo "[8/9] Verificando nginx en puerto 2080..."

if sudo ss -tulpn | grep -q ":2080"; then
    echo "OK: nginx escucha en puerto 2080"
else
    echo "ERROR: Nada escucha en puerto 2080"
    sudo ss -tulpn | grep nginx || true
    exit 1
fi

echo "[9/9] Verificando openNDS..."

if sudo ndsctl status > /tmp/nds_status.txt 2>&1; then
    echo "OK: openNDS responde"
    cat /tmp/nds_status.txt | grep -E "Managed interface|MHD Server|FAS:|Current clients" || true
else
    echo "ERROR: ndsctl no responde"
    cat /tmp/nds_status.txt
    exit 1
fi

echo "======================================"
echo " Hotspot WifiGEY levantado correctamente"
echo "======================================"
echo "WiFi: WifiGEY"
echo "Portal: http://192.168.200.1:2080/portal/login.php"
echo "openNDS: http://192.168.200.1:2050"
echo "======================================"