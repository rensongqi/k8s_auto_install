#!/bin/bash
# Author: Rensongqi
# Email: cactirsq@163.com

while :
do
    read -p "Please enter the network plugin you want to download [flannel|calico]: " name
    if [ $name == "flannel" -o $name == "calico" ]
    then
        break
    else
        echo "Your input error, please enter [flannel|calico]"
    fi
done

# step 1. copy repos & config hosts file
\cp ./repos/* /etc/yum.repos.d/

IP=`hostname -I | awk '{print $1}'`
cat >>/etc/hosts<<EOF
$IP master
EOF

# step 2. Close firewalld & selinux
sudo systemctl stop firewalld
sudo systemctl disable firewalld

sudo setenforce 0
sudo sed -i 's/SELINUX=enforcing/SELINUX=disabled/g' /etc/selinux/config

# step 3. Close swap
sudo swapoff -a
sudo sed -ri 's/.*swap.*/#&/' /etc/fstab

# step 4 Config ipvs
sudo yum install ipvsadm -y
sudo chmod +x ./scripts/ipvs.sh
sudo bash ./scripts/ipvs.sh
sudo lsmod | grep ip_vs
line=`lsmod | grep ip_vs | wc -l`
if [ $line -gt 3 ]
then
    echo "************************ipvs load successfully!************************"
    echo ""
    echo ""
else
    echo "************************ipvs load failed!************************"
    exit 1
fi

# step 5. Get kubelet kubeadm pkg and so on ...
sudo yum install kubelet-1.18.3-0.x86_64 kubeadm-1.18.3-0.x86_64 kubectl-1.18.3-0.x86_64 docker-ce -y
sudo systemctl enable kubelet && sudo systemctl enable docker && sudo systemctl start docker

# step 6. Config docker daemon.json
sudo mkdir -p /etc/docker
sudo tee /etc/docker/daemon.json <<-'EOF'
{
  "registry-mirrors": ["https://3po4uu60.mirror.aliyuncs.com"]
}
EOF
sudo systemctl daemon-reload
sudo systemctl restart docker
echo ""
echo ""

# step 7. Download K8s images
echo "************************K8s images Downloading************************"
for i in kube-apiserver:v1.18.3 kube-controller-manager:v1.18.3 kube-scheduler:v1.18.3 kube-proxy:v1.18.3 pause:3.2 etcd:3.4.3-0 coredns:1.6.7
do
    docker pull registry.cn-shanghai.aliyuncs.com/rsq_k8s_images/$i
done
echo ""
echo ""

echo "************************Network plugin install************************"
if [ "$name" == "flannel" ]
then
    echo "Please wait a moment..."
    docker pull registry.cn-shanghai.aliyuncs.com/rsq_k8s_images/flannel:v0.13.1-rc1
    break
elif [ "$name" == "calico" ]
then
    echo "Please wait a moment..."
    docker push registry.cn-shanghai.aliyuncs.com/rsq_k8s_images/node:v3.8.2
    docker push registry.cn-shanghai.aliyuncs.com/rsq_k8s_images/cni:v3.8.2
    docker push registry.cn-shanghai.aliyuncs.com/rsq_k8s_images/kube-controllers:v3.8.2
    docker push registry.cn-shanghai.aliyuncs.com/rsq_k8s_images/pod2daemon-flexvol:v3.8.2
    break
else
    echo "Your input error, please enter [flannel|calico]"
fi
echo ""
echo ""

echo "************************Change docker tag************************"
if [ "$name" == "flannel" ]
then
	sudo docker tag registry.cn-shanghai.aliyuncs.com/rsq_k8s_images/flannel:v0.13.1-rc1 quay.io/coreos/flannel:v0.13.1-rc1
	sudo docker rmi registry.cn-shanghai.aliyuncs.com/rsq_k8s_images/flannel:v0.13.1-rc1
elif [ "$name" == "calico" ]
then
    for i in node:v3.8.2 cni:v3.8.2 kube-controllers:v3.8.2 pod2daemon-flexvol:v3.8.2
    do
        sudo docker tag registry.cn-shanghai.aliyuncs.com/rsq_k8s_images/$i calico/$i
	    sudo docker rmi registry.cn-shanghai.aliyuncs.com/rsq_k8s_images/$i
    done
fi

sudo docker images |grep rsq_k8s_images |awk '{print "docker tag",$1":"$2,$1":"$2}' |sed -e 's#registry.cn-shanghai.aliyuncs.com/rsq_k8s_images#k8s.gcr.io#2' | sh -x
echo ""
echo "************************Docker images download successfully************************"


# step 8. Open iptables rule and ip_forward
sudo echo 1 > /proc/sys/net/bridge/bridge-nf-call-ip6tables 
sudo echo 1 > /proc/sys/net/bridge/bridge-nf-call-iptables
sudo echo 1 > /proc/sys/net/ipv4/ip_forward
sudo cat >>/etc/rc.local<<EOF
echo 1 > /proc/sys/net/bridge/bridge-nf-call-ip6tables 
echo 1 > /proc/sys/net/bridge/bridge-nf-call-iptables
echo 1 > /proc/sys/net/ipv4/ip_forward
EOF

# step 9. Kubeadm init
sudo kubeadm init --config ./scripts/kubeadm-config-latest.yaml --ignore-preflight-errors=Swap

if [ "$?" != 0 ] ; then
   echo "kubeadm init Failed!!!"
   exit 2
fi

mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config

# step 10. Apply network plugin
if [ "$name" == "flannel" ]
then
	sudo kubectl apply -f ./plugins/flannel_v0.13.1/kube-flannel.yml
elif [ "$name" == "calico" ]
then
	sudo kubectl apply -f ./plugins/calico_v3.17.0/tigera-operator.yaml
	sudo kubectl apply -f ./plugins/calico_v3.17.0/custom-resources.yaml
fi

# step 11. Config Master schedulable
# sudo kubectl taint nodes --all node-role.kubernetes.io/master-
