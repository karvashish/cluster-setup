# cluster-setup

## Single-node example
<<<
./ansible-setup.sh \
  --control-hostname control-sys \
  --control-ip 192.168.1.240 \
  --group pis \
  --node node-1 192.168.1.241 \
  --ssh-user "$(whoami)"
<<<

## Multi-node example
<<<
./ansible-setup.sh \
  --control-hostname control-sys \
  --control-ip 192.168.1.240 \
  --group pis \
  --node node-1 192.168.1.241 \
  --node node-2 192.168.1.242 \
  --ssh-user "$(whoami)"
<<<
