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
    template = "${file("./cloud-config/etcd_init.yaml")}"

    vars {
      discovery_token = "${etcd_discovery.etcd_cluster_token.url}"
    }
}






resource "template_file" "flannel_opts_master" {
    template = "${file("./common/systemd/flannel-opts.env")}"
    vars {
      advertise_ip = "${digitalocean_droplet.master.ipv4_address}"
      etcd_endpoints = "${join(",", format("http://%v:2379", digitalocean_droplet.*.ipv4_address_private))}"
    }
}

resource "template_file" "flannel_opts_minion" {
    count = "${var.minion_count}"
    template = "${file("./common/systemd/flannel-opts.env")}"
    vars {
      advertise_ip = "${element(digitalocean_droplet.minion.*.ipv4_address, count.index)}"
      etcd_endpoints = "${join(",", format("http://%v:2379", digitalocean_droplet.*.ipv4_address_private))}"
    }
}





resource "template_file" "master_apiserver" {
      template = "${file("./master/manifests/kube-apiserver.yaml")}"
      vars {
        k8s_version = "${var.k8s_version}"
        advertise_ip = "${digitalocean_droplet.master.ipv4_address}"
        etcd_endpoints = "${join(",", format("http://%v:2379", digitalocean_droplet.*.ipv4_address_private))}"
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
    etcd_endpoints = "${join(",", format("http://%v:2379", digitalocean_droplet.*.ipv4_address_private))}"
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
        inline = [
          "mkdir keys",
          "openssl genrsa -out ./keys/ca-key.pem 2048",
          "openssl req -x509 -new -nodes -key ./keys/ca-key.pem -days 10000 -out ./keys/ca.pem -subj /CN=kube-ca",

          "openssl genrsa -out ./keys/apiserver-key.pem 2048",
          "echo ${template_file.tls_config_file.rendered} > ./keys/openssl.conf",
          "openssl req -new -key ./keys/apiserver-key.pem -out apiserver.csr -subj /CN=kube-apiserver -config ./keys/openssl.conf",
          "openssl x509 -req -in ./keys/apiserver.csr -CA ./keys/ca.pem -CAkey ./keys/ca-key.pem -CAcreateserial -out ./keys/apiserver.pem -days 365 -extensions v3_req -extfile ./keys/openssl.conf",

          "openssl genrsa -out ./keys/worker-key.pem 2048",
          "openssl req -new -key ./keys/worker-key.pem -out ./keys/worker.csr -subj /CN=kube-worker",
          "openssl x509 -req -in ./keys/worker.csr -CA ./keys/ca.pem -CAkey ./keys/ca-key.pem -CAcreateserial -out ./keys/worker.pem -days 365",

          "openssl genrsa -out ./keys/admin-key.pem 2048",
          "openssl req -new -key ./keys/admin-key.pem -out ./keys/admin.csr -subj /CN=kube-admin",
          "openssl x509 -req -in ./keys/admin.csr -CA ./keys/ca.pem -CAkey ./keys/ca-key.pem -CAcreateserial -out ./keys/admin.pem -days 365"
        ]
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
