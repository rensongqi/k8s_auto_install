# K8s auto install in for Centos7



## 1. Git clone

```bash
git clone http://git.51vr.local/ivt_cloud/cloud_deploy.git
```



## 2. Exec k8s_auto_install.sh

```
cd cloud_deploy/k8s_auto_install/
sudo chmod +x k8s_auto_install.sh
./k8s_auto_install.sh
```



## 3. You need to select the type of network plug-in during installation


```bash
# flannel version:v0.13.1
# calico version:v3.17.0

************************Network plugin install************************
Please enter the network plugin you want to download [flannel|calico]: flannel
Please wait a moment...

```



## 4 Node join cluster

```bash
# exec the following commands on node
git clone http://git.51vr.local/ivt_cloud/cloud_deploy.git
cd cloud_deploy/k8s_auto_install/
sudo chmod +x k8s_node_join.sh
./k8s_node_join.sh

# Then we need to exec get_token.sh on master
sudo chmod +x get_token.sh
./get_token.sh
```



## 5. Docker image registry

```bash
# Contains images related to K8S, Calico & Flannel
registry.cn-shanghai.aliyuncs.com/rsq_k8s_images/
```
