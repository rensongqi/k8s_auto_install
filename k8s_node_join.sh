#!/bin/bash
# Author: Rensongqi
# Email: cactirsq@163.com

REGULAR1="^[0-9].[0-9][0-9].[0-9][0-9]$"
REGULAR2="^[0-9].[0-9][0-9].[0-9]$"
while :
do
    read -p "Please enter the network plugin you want to download [flannel|calico]: " NAME
    if [ $NAME != "flannel" -a $NAME != "calico" ]; then
        echo "Your input error, please enter [flannel|calico]"
        break
    fi

    read -p "Please enter the node hostname: " NODE_HOSTNAME
    read -p "Please enter the master ip: " MASTER_IP
    read -p "Please enter the master hostname: " MASTER_HOSTNAME

    read -p "Please enter the version of K8S you want to install eg.[1.18.3|1.19.4|...]: " VERSION
    if [[ $VERSION =~ $REGULAR1 || $VERSION =~ $REGULAR2 ]]; then
        break
    else
        echo "Your input error, please enter [1.18.3|1.19.4|...]"
        break
    fi
done

echo ""
echo ""
echo -e "\033[33m##################################### step 1. Node init #####################################\033[0m"
\cp ./repos/* /etc/yum.repos.d/
sudo yum makecache

NODE_IP=`hostname -I | awk '{print $1}'`
cat >>/etc/hosts<<EOF
$NODE_IP $NODE_HOSTNAME
$MASTER_IP $MASTER_HOSTNAME
EOF

hostnamectl set-hostname $NODE_HOSTNAME

echo ""
echo ""
echo -e "\033[33m######################### step 2. Close firewalld & selinux & swap ##########################\033[0m"
sudo systemctl stop firewalld
sudo systemctl disable firewalld

sudo setenforce 0
sudo sed -i 's/SELINUX=enforcing/SELINUX=disabled/g' /etc/selinux/config

sudo swapoff -a
sudo sed -ri 's/.*swap.*/#&/' /etc/fstab

echo ""
echo ""
echo -e "\033[33m####################### step 3. Get kubelet kubeadm pkg and so on ... #######################\033[0m"
sudo yum install kubelet-${VERSION}-0.x86_64 kubeadm-${VERSION}-0.x86_64 kubectl-${VERSION}-0.x86_64 docker-ce-cli-19.03.12-3.el7 docker-ce-19.03.12-3.el7 -y
sudo systemctl enable kubelet && sudo systemctl enable docker && sudo systemctl start docker

echo ""
echo ""
echo -e "\033[33m############################# step 4. Config docker daemon.json #############################\033[0m"
sudo mkdir -p /etc/docker
sudo tee /etc/docker/daemon.json <<-'EOF'
{
  "registry-mirrors": ["https://3po4uu60.mirror.aliyuncs.com"],
  "exec-opts":["native.cgroupdriver=cgroupfs"]
}
EOF
sudo systemctl daemon-reload
sudo systemctl restart docker

echo ""
echo ""
echo -e "\033[33m######################### step 5. Open iptables rule and ip_forward #########################\033[0m"
sudo echo 1 > /proc/sys/net/bridge/bridge-nf-call-ip6tables 
sudo echo 1 > /proc/sys/net/bridge/bridge-nf-call-iptables
sudo echo 1 > /proc/sys/net/ipv4/ip_forward
sudo cat >>/etc/rc.local<<EOF
echo 1 > /proc/sys/net/bridge/bridge-nf-call-ip6tables 
echo 1 > /proc/sys/net/bridge/bridge-nf-call-iptables
echo 1 > /proc/sys/net/ipv4/ip_forward
EOF

echo ""
echo ""
echo -e "\033[33m################################# step 6. Node Join Cluster #################################\033[0m"
echo -e "\033[32mYou will need to manually execute the script on Master for get kubeadm join command: [./get_token.sh]\033[0m"
echo -e "\033[33m#############################################################################################\033[0m"
