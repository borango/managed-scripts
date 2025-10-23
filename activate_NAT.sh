sudo iptables -A POSTROUTING -o wwan0       -t nat       -j MASQUERADE
sudo iptables -A FORWARD     -o wwan0 -i enx0050b6c13fc4 -j ACCEPT
sudo iptables -A FORWARD     -i wwan0 -o enx0050b6c13fc4 -j ACCEPT -m state --state RELATED,ESTABLISHED
