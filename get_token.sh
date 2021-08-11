#!/bin/bash

read -p "Pls input the node IP:" NODE_IP
read -p "Pls input the node hostname:" NODE_HOSTNAME

cat >>/etc/hosts<<EOF
$NODE_IP $NODE_HOSTNAME
EOF

kubeadm token create >/dev/null 2>&1
TOKEN=`kubeadm token list | awk 'END{print $1}'`
HASH=`openssl x509 -pubkey -in /etc/kubernetes/pki/ca.crt | openssl rsa -pubin -outform der 2>/dev/null | openssl dgst -sha256 -hex | sed 's/^.* //'`
IP=`hostname -I | awk '{print $1}'`

echo ""
echo ""
echo "You will need to manually execute the following commands on $NODE_IP"
echo ""
echo "***************************************************************************************************************"
echo "kubeadm join $IP:6443 --token $TOKEN --discovery-token-ca-cert-hash sha256:$HASH --ignore-preflight-errors=Swap"
echo "***************************************************************************************************************"
