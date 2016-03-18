Last updated and tested with kubernetes v1.2.0

---

A terraform project for provisioning and scaling kubernetes clusters at digital ocean.
You'll be prompted for your digital ocean token when running plan and apply. It will
use your public key at ~/.ssh/id_rsa.pub when provisioning the nodes.

#### Warning
This does not produce a secure / production ready cluster. In order to properly
secure your cluster you must run a secure etcd cluster (which this config does
not create) and ideally you should be using something like the OpenID integration
or keystone authentication mechanisms. You should also have mechanisms in place to
ensure security updates, and lock down unnecessary ports.

#### Dependencies
* terraform binaries on your path: http://www.terraform.io/downloads.html
* terraform add-on provider for etcd: https://github.com/bakins/terraform-provider-etcd
* kubectl binary on your path (to configure the cluster context)



Basic usage (1 master and 2 minions):
```bash
# determine what needs to happen to reach your desired state
terraform plan

# do the necessary things to reach desired state
terraform apply

# automatically configures your local kubectl and embeds the certs in the conf
kubectl get nodes
```


Larger scale (1 master and 21 minions):
```bash
# determine what needs to happen to reach your desired state
terraform plan -var 'minion_count=21' -var 'do_token=<token>'

# do the necessary things to reach desired state
terraform apply -var 'minion_count=21' -var 'do_token=<token>'

# automatically configures your local kubectl and embeds the certs in the conf
kubectl get nodes
```




Variables:
With terraform you can specify variables when planning and applying.
Most options are exposed as variables for this kubernetes configuration.

```hcl
variable "do_token" {}

# subnet available for pod IPs
variable "pod_network_subnet" {
  default = "10.2.0.0/16"
}

# subnet available for services
variable "service_ip_range" {
  default = "10.3.0.0/24"
}

# hardcoded dns service ip
variable "dns_service_ip" {
  default = "10.3.0.10"
}

# hardcoded kubernetes service ip
variable "k8s_service_ip" {
  default = "10.3.0.1"
}

# digital ocean operating system (only coreos-beta is supported atm)
variable "os" {
  default = "coreos-beta"
}

# region to provision the VMs in
variable "region" {
  default = "nyc2"
}

# size of the master node
variable "master_size" {
  default = "512mb"
}

# size of each minion node
variable "minion_size" {
  default = "1gb"
}

# number of minions to create for the cluster
variable "minion_count" {
  default = 2
}

# prefix to use on the VM names
variable "prefix" {
  default = "kube"
}

# kubernetes version to deploy
variable "k8s_version" {
  default = "v1.2.0"
}

# name of the cluster to configure for kubectl
variable "cluster_name" {
  default = "kube-cluster"
}

# name of the user to configure for kubectl
variable "cluster_user" {
  default = "kube-user"
}

# name of the context to configure for kubectl
variable "context_name" {
  default = "kube-kube"
}
```
