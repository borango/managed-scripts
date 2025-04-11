sudo iptables -t nat -A POSTROUTING -o wlp4s0 -j MASQUERADE
sudo iptables -A FORWARD -o wlp4s0 -i enx0050b6c13fc4                                      -j ACCEPT
sudo iptables -A FORWARD -i wlp4s0 -o enx0050b6c13fc4 -m state --state RELATED,ESTABLISHED -j ACCEPT

