#!/usr/bin/env bash
# Test script to verify VPN namespace is working correctly

set -e

echo "================================================"
echo "VPN Namespace Test Script"
echo "================================================"
echo ""

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${BLUE}=== 1. Host Network Test ===${NC}"
echo "Host IP address:"
HOST_IP=$(curl -s --max-time 5 -4 ifconfig.me)
echo -e "${GREEN}$HOST_IP${NC}"
echo ""

echo -e "${BLUE}=== 2. VPN Namespace Test ===${NC}"
echo "Namespace IP address (should be VPN IP):"
NAMESPACE_IP=$(sudo ip netns exec vpn curl -s --max-time 5 -4 ifconfig.me)
echo -e "${GREEN}$NAMESPACE_IP${NC}"
echo ""

echo -e "${BLUE}=== 3. VPN Location Check ===${NC}"
echo "Checking VPN geolocation:"
sudo ip netns exec vpn curl -s --max-time 5 https://ipapi.co/json/ | jq -r '"\(.city), \(.country_name) (\(.org))"'
echo ""

echo -e "${BLUE}=== 4. DNS Leak Test ===${NC}"
echo "Namespace DNS servers:"
sudo ip netns exec vpn cat /etc/resolv.conf | grep nameserver
echo ""

echo -e "${BLUE}=== 5. Prowlarr Network Test ===${NC}"
if systemctl is-active --quiet prowlarr; then
    PROWLARR_PID=$(systemctl show prowlarr --property=MainPID --value)
    echo "Prowlarr is running (PID: $PROWLARR_PID)"
    echo "Prowlarr sees this IP:"
    PROWLARR_IP=$(sudo nsenter -t $PROWLARR_PID -n curl -s --max-time 5 https://api.ipify.org)
    echo -e "${GREEN}$PROWLARR_IP${NC}"
else
    echo -e "${YELLOW}Prowlarr is not running${NC}"
fi
echo ""

echo -e "${BLUE}=== 6. Sonarr Network Test ===${NC}"
if systemctl is-active --quiet sonarr; then
    SONARR_PID=$(systemctl show sonarr --property=MainPID --value)
    echo "Sonarr is running (PID: $SONARR_PID)"
    echo "Sonarr sees this IP:"
    SONARR_IP=$(sudo nsenter -t $SONARR_PID -n curl -s --max-time 5 https://api.ipify.org)
    echo -e "${GREEN}$SONARR_IP${NC}"
else
    echo -e "${YELLOW}Sonarr is not running${NC}"
fi
echo ""

echo -e "${BLUE}=== 7. Radarr Network Test ===${NC}"
if systemctl is-active --quiet radarr; then
    RADARR_PID=$(systemctl show radarr --property=MainPID --value)
    echo "Radarr is running (PID: $RADARR_PID)"
    echo "Radarr sees this IP:"
    RADARR_IP=$(sudo nsenter -t $RADARR_PID -n curl -s --max-time 5 https://api.ipify.org)
    echo -e "${GREEN}$RADARR_IP${NC}"
else
    echo -e "${YELLOW}Radarr is not running${NC}"
fi
echo ""

echo -e "${BLUE}=== Summary ===${NC}"
echo "Host IP:      $HOST_IP"
echo "Namespace IP: $NAMESPACE_IP"

if [ "$HOST_IP" != "$NAMESPACE_IP" ]; then
    echo -e "${GREEN}✓ VPN namespace is working correctly!${NC}"
    echo -e "${GREEN}✓ Traffic is going through VPN${NC}"
else
    echo -e "${YELLOW}⚠ Warning: Host and namespace IPs are the same${NC}"
    echo -e "${YELLOW}⚠ VPN might not be working correctly${NC}"
fi

echo ""
echo "================================================"
echo "Test Complete"
echo "================================================"
