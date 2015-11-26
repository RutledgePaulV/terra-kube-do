variable "do_token" {}

variable "pod_network_subnet" {
  default = "10.2.0.0/16"
}

variable "service_ip_range" {
  default = "10.3.0.0/24"
}

variable "dns_service_ip" {
  default = "10.3.0.10"
}

variable "k8s_service_ip" {
  default = "10.3.0.1"
}

variable "os" {
  default = "coreos-beta"
}

variable "region" {
  default = "nyc2"
}

variable "master_size" {
  default = "512mb"
}

variable "minion_size" {
  default = "1gb"
}

variable "minion_count" {
  default = 2
}

variable "prefix" {
  default = "kube"
}

variable "k8s_version" {
  default = "1.1.2"
}

provider "digitalocean" {
    token = "${var.do_token}"
}

resource "digitalocean_ssh_key" "default" {
    name = "My Public Key"
    public_key = "${file("~/.ssh/id_rsa.pub")}"
}




resource "etcd_discovery" "etcd_cluster_token" {
   size = "${var.minion_count + 1}"
}

resource "template_file" "cloud_config" {
    template = "${file("./common/cloud-config/etcd_init.yaml")}"

    vars {
      discovery_token = "${etcd_discovery.etcd_cluster_token.url}"
    }
}






resource "template_file" "flannel_opts_master" {
    template = "${file("./common/systemd/flannel-opts.env")}"
    vars {
      advertise_ip = "${digitalocean_droplet.master.ipv4_address}"
      etcd_endpoints = "${digitalocean_droplet.master.ipv4_address_private},${join(",", formatlist("http://%s:2379", digitalocean_droplet.minion.*.ipv4_address_private))}"
    }
}

resource "template_file" "flannel_opts_minion" {
    count = "${var.minion_count}"
    template = "${file("./common/systemd/flannel-opts.env")}"
    vars {
      advertise_ip = "${element(digitalocean_droplet.minion.*.ipv4_address, count.index)}"
      etcd_endpoints = "${digitalocean_droplet.master.ipv4_address_private},${join(",", formatlist("http://%s:2379", digitalocean_droplet.minion.*.ipv4_address_private))}"
    }
}



resource "template_file" "master_kubelet" {
    template = "${file("./master/systemd/kubelet.service")}"
    vars {
      advertise_ip = "${digitalocean_droplet.master.ipv4_address}"
      dns_service_ip = "${var.dns_service_ip}"
    }
}

resource "template_file" "master_apiserver" {
      template = "${file("./master/manifests/kube-apiserver.yaml")}"
      vars {
        k8s_version = "${var.k8s_version}"
        advertise_ip = "${digitalocean_droplet.master.ipv4_address}"
        etcd_endpoints = "${digitalocean_droplet.master.ipv4_address_private},${join(",", formatlist("http://%s:2379", digitalocean_droplet.minion.*.ipv4_address_private))}"
        service_ip_range = "${var.service_ip_range}"
      }
}

resource "template_file" "master_controller_manager" {
  template = "${file("./master/manifests/kube-controller-manager.yaml")}"
  vars {
    k8s_version = "${var.k8s_version}"
  }
}

resource "template_file" "master_podmaster" {
  template = "${file("./master/manifests/kube-podmaster.yaml")}"
  vars {
    advertise_ip = "${digitalocean_droplet.master.ipv4_address}"
    etcd_endpoints = "${digitalocean_droplet.master.ipv4_address_private},${join(",", formatlist("http://%s:2379", digitalocean_droplet.minion.*.ipv4_address_private))}"
  }
}

resource "template_file" "master_proxy" {
  template = "${file("./master/manifests/kube-proxy.yaml")}"
  vars {
    k8s_version = "${var.k8s_version}"
  }
}

resource "template_file" "master_scheduler" {
  template = "${file("./master/manifests/kube-scheduler.yaml")}"
  vars {
    k8s_version = "${var.k8s_version}"
  }
}



resource "template_file" "minion_kubelet" {
    count = "${var.minion_count}"
    template = "${file("./minions/systemd/kubelet.service")}"
    vars {
      master_ip = "${digitalocean_droplet.master.ipv4_address}"
      advertise_ip = "${element(digitalocean_droplet.minion.*.ipv4_address, count.index)}"
      dns_service_ip = "${var.dns_service_ip}"
    }
}

resource "template_file" "minion_proxy" {
  template = "${file("./minions/manifests/kube-proxy.yaml")}"
  vars {
    k8s_version = "${var.k8s_version}"
    master_ip = "${digitalocean_droplet.master.ipv4_address}"
  }
}

resource "template_file" "worker-kubeconfig" {
  template = "${file("./minions/manifests/worker-kubeconfig.yaml")}"
  vars {}
}



resource "template_file" "tls_config_file" {
    template = "${file("./tls/openssl.conf")}"

    vars {
      k8s_service_ip = "${var.k8s_service_ip}"
      master_public_ip = "${digitalocean_droplet.master.ipv4_address}"
    }
}

resource "null_resource" "keys" {
    triggers {
        master_id = "${digitalocean_droplet.master.id}"
    }

    provisioner "local-exec" {
        command = "mkdir ./keys && echo ${template_file.tls_config_file.rendered} > ./keys/openssl.conf"
    }

    provisioner "local-exec" {
      command = "sh ./keys.sh"
    }
}





resource "digitalocean_droplet" "master" {
    image = "${var.os}"
    name = "${var.prefix}-master"
    region = "${var.region}"
    size = "${var.master_size}"
    user_data = "${template_file.cloud_config.rendered}"
    ssh_keys = ["${digitalocean_ssh_key.default.id}"]
    private_networking = true
}

resource "digitalocean_droplet" "minion" {
  count = "${var.minion_count}"
  image = "${var.os}"
  name = "${var.prefix}-minion-${count.index}"
  region = "${var.region}"
  size = "${var.minion_size}"
  user_data = "${template_file.cloud_config.rendered}"
  ssh_keys = ["${digitalocean_ssh_key.default.id}"]
  private_networking = true
}
