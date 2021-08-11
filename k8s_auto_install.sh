#!/bin/bash
# Author: Rensongqi
# Email: cactirsq@163.com

echo -e "\033[33m###################### K8s Auto Install Scripts Description ###################### \033[0m"
echo -e "\033[32m#\033[0m"
echo -e "\033[32m# 1. Flannel Version: 0.13.1 \033[0m"
echo -e "\033[32m# 2. Calico Version: Latest \033[0m"
echo -e "\033[32m# 3. Kubernetes Version: Custom \033[0m"
echo -e "\033[32m# 4. CIDR: 10.244.0.0/16 \033[0m"
echo -e "\033[32m# \033[0m"
echo -e "\033[33m################################################################################## \033[0m"

REGULAR1="^[0-9].[0-9][0-9].[0-9][0-9]$"
REGULAR2="^[0-9].[0-9][0-9].[0-9]$"
while :
do 
    read -p "Please enter the network plugin you want to download [flannel|calico]: " NAME
    if [ $NAME != "flannel" -a $NAME != "calico" ]; then
        echo "Your input error, please enter [flannel|calico]"
        break
    fi

    read -p "Please enter the hostname: " HOSTNAME

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
echo -e "\033[33m##################### step 1. copy repos & config hosts file & change hostname ##################### \033[0m"
\cp ./repos/* /etc/yum.repos.d/
sudo yum makecache

IP=`hostname -I | awk '{print $1}'`
cat >/etc/hosts<<EOF
127.0.0.1   localhost localhost.localdomain localhost4 localhost4.localdomain4
::1         localhost localhost.localdomain localhost6 localhost6.localdomain6
$IP $HOSTNAME
EOF

sudo hostnamectl set-hostname $HOSTNAME

echo ""
echo ""
echo -e "\033[33m############################# step 2. Close firewalld & selinux & swap ############################# \033[0m"
sudo systemctl stop firewalld
sudo systemctl disable firewalld

sudo setenforce 0
sudo sed -i 's/SELINUX=enforcing/SELINUX=disabled/g' /etc/selinux/config

sudo swapoff -a
sudo sed -ri 's/.*swap.*/#&/' /etc/fstab

echo ""
echo ""
echo -e "\033[33m######################################## step 3 Config ipvs ######################################## \033[0m"
sudo yum install ipvsadm -y
modprobe -- ip_vs
modprobe -- ip_vs_sh
modprobe -- ip_vs_rr
modprobe -- ip_vs_wrr
modprobe -- nf_conntrack_ipv4
sudo lsmod | grep ip_vs
line=`lsmod | grep ip_vs | wc -l`
if [ $line -gt 3 ]; then
    echo -e "\033[32m************************ipvs load successfully!************************ \033[0m"
    echo ""
    echo ""
else
    echo -e "\033[31m***************************ipvs load failed!*************************** \033[0m"
    exit 1
fi

echo ""
echo ""
echo -e "\033[33m########################## step 4. Get kubelet kubeadm pkg and so on ... ########################### \033[0m"
sudo yum install kubelet-${VERSION}-0.x86_64 kubeadm-${VERSION}-0.x86_64 kubectl-${VERSION}-0.x86_64 docker-ce-cli-19.03.12-3.el7 docker-ce-19.03.12-3.el7 -y
sudo systemctl enable kubelet && sudo systemctl enable docker && sudo systemctl start docker

echo ""
echo ""
echo -e "\033[33m################################ step 5. Config docker daemon.json ################################# \033[0m"
sudo mkdir -p /etc/docker
sudo tee /etc/docker/daemon.json <<-'EOF'
{
"insecure-registries": ["images.51vr.local:5000"],
"registry-mirrors": ["https://3po4uu60.mirror.aliyuncs.com"]
}
EOF
sudo systemctl daemon-reload
sudo systemctl restart docker

echo ""
echo ""
echo -e "\033[33m############################ step 6. Open iptables rule and ip_forward  ############################ \033[0m"
sudo echo 1 > /proc/sys/net/bridge/bridge-nf-call-ip6tables 
sudo echo 1 > /proc/sys/net/bridge/bridge-nf-call-iptables
sudo echo 1 > /proc/sys/net/ipv4/ip_forward
sudo cat >>/etc/sysctl.conf<<EOF
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables = 1
net.ipv4.ip_forward = 1
EOF
sysctl -p

echo ""
echo ""
echo -e "\033[33m###################################### step 7. Kubeadm init  ####################################### \033[0m"
sudo sed -i "s/VERSION/$VERSION/g" ./scripts/kubeadm-config-latest.yaml
sudo kubeadm init --config ./scripts/kubeadm-config-latest.yaml --ignore-preflight-errors=Swap

if [ "$?" != 0 ]; then
   echo "kubeadm init Failed!!!"
   exit 2
fi

mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config

echo ""
echo ""
echo -e "\033[33m################################## step 8. Apply network plugin  ################################### \033[0m"
if [ "$NAME" == "flannel" ]; then
    sudo kubectl apply -f ./plugins/flannel_v0.13.1/kube-flannel.yml
elif [ "$NAME" == "calico" ]; then
    sudo kubectl create -f ./plugins/calico_v3.20.0/tigera-operator.yaml
    sudo kubectl create -f ./plugins/calico_v3.20.0/custom-resources.yaml
fi

echo ""
echo ""
echo -e "\033[33m################################ step 9. Config Master schedulable  ################################ \033[0m"
# sudo kubectl taint nodes --all node-role.kubernetes.io/master-

# revert kubeadm-config file
sudo sed -i "s/$VERSION/VERSION/g" ./scripts/kubeadm-config-latest.yaml

echo -e "\033[32m########################### The K8s v$VERSION is successfully installed  ########################### \033[0m"
