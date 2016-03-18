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
  default = "v1.2.0"
}

variable "cluster_name" {
  default = "kube-cluster"
}

variable "cluster_user" {
  default = "kube-user"
}

variable "context_name" {
  default = "kube-kube"
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
      etcd_endpoints = "http://${digitalocean_droplet.master.ipv4_address_private}:2379,${join(",", formatlist("http://%s:2379", digitalocean_droplet.minion.*.ipv4_address_private))}"
    }
}

resource "template_file" "flannel_opts_minion" {
    count = "${var.minion_count}"
    template = "${file("./common/systemd/flannel-opts.env")}"
    vars {
      advertise_ip = "${element(digitalocean_droplet.minion.*.ipv4_address, count.index)}"
      etcd_endpoints = "http://${digitalocean_droplet.master.ipv4_address_private}:2379,${join(",", formatlist("http://%s:2379", digitalocean_droplet.minion.*.ipv4_address_private))}"
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
        etcd_endpoints = "http://${digitalocean_droplet.master.ipv4_address_private}:2379,${join(",", formatlist("http://%s:2379", digitalocean_droplet.minion.*.ipv4_address_private))}"
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
    etcd_endpoints = "http://${digitalocean_droplet.master.ipv4_address_private}:2379,${join(",", formatlist("http://%s:2379", digitalocean_droplet.minion.*.ipv4_address_private))}"
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

resource "template_file" "worker_kubeconfig" {
  template = "${file("./minions/manifests/worker-kubeconfig.yaml")}"
  vars {}
}


resource "template_file" "init_flannel" {
  template = "${file("./init_flannel.sh")}"
  vars {
    pod_network_subnet = "${var.pod_network_subnet}"
    master_private_ip = "${digitalocean_droplet.master.ipv4_address_private}"
  }
}

resource "template_file" "dns_addon" {
  template = "${file("./common/addons/dns_addon.yaml")}"
  vars {
    dns_service_ip = "${var.dns_service_ip}"
  }
}

resource "template_file" "tls_config_file" {
    template = "${file("./local/openssl.conf")}"
    vars {
      k8s_service_ip = "${var.k8s_service_ip}"
      master_public_ip = "${digitalocean_droplet.master.ipv4_address}"
    }
}


resource "template_file" "kubectl_init" {
    template = "${file("./local/kubectl.sh")}"
    vars {
        cluster_name = "${var.cluster_name}"
        cluster_user = "${var.cluster_user}"
        context_name = "${var.context_name}"
        master_ip = "${digitalocean_droplet.master.ipv4_address}"
        ca_cert = "./keys/ca.pem"
        admin_cert = "./keys/admin.pem"
        admin_key = "./keys/admin-key.pem"
    }
}



resource "null_resource" "keys" {
    triggers {
        master_id = "${digitalocean_droplet.master.id}"
    }

    provisioner "local-exec" {
        command = "mkdir -p ./keys && echo '${template_file.tls_config_file.rendered}' > ./keys/openssl.conf"
    }

    provisioner "local-exec" {
        command = "chmod +x ./keys.sh && ./keys.sh"
    }
}


resource "null_resource" "kubectl" {

    triggers {
        master_id = "${digitalocean_droplet.master.id}"
    }

    provisioner "local-exec" {
        command = "echo '${template_file.kubectl_init.rendered}' > ./kubectl.sh && chmod +x ./kubectl.sh && ./kubectl.sh"
    }

}


resource "null_resource" "master_provisioning" {

      provisioner "file" {
            source = "./keys/"
            destination = "/etc/kubernetes/ssl/"
            connection = {
            host = "${digitalocean_droplet.master.ipv4_address}"
              user = "core"
              agent = true
            }
        }

      provisioner "remote-exec" {
        inline = [
            "cat << EOF > /etc/flannel/options.env",
            "${template_file.flannel_opts_master.rendered}",
            "EOF",

            "cat << EOF > /etc/kubernetes/manifests/kube-proxy.yaml",
            "${template_file.master_proxy.rendered}",
            "EOF",

            "cat << EOF > /srv/kubernetes/manifests/kube-scheduler.yaml",
            "${template_file.master_scheduler.rendered}",
            "EOF",

            "cat << EOF > /srv/kubernetes/manifests/kube-controller-manager.yaml",
            "${template_file.master_controller_manager.rendered}",
            "EOF",

            "cat << EOF > /etc/kubernetes/manifests/kube-podmaster.yaml",
            "${template_file.master_podmaster.rendered}",
            "EOF",

            "cat << EOF > /etc/kubernetes/manifests/kube-apiserver.yaml",
            "${template_file.master_apiserver.rendered}",
            "EOF",

            "cat << EOF > /etc/systemd/system/kubelet.service",
            "${template_file.master_kubelet.rendered}",
            "EOF",

            "cat << EOF > /etc/kubernetes/init_flannel.sh",
            "${template_file.init_flannel.rendered}",
            "EOF",

            "sudo chmod +x /etc/kubernetes/init_flannel.sh",
            "sudo systemctl daemon-reload",
            "sudo systemctl start etcd2",
            "sudo /etc/kubernetes/init_flannel.sh",
            "sudo systemctl start flanneld",
            "sudo systemctl start docker",
            "sudo systemctl start kubelet",
            "sudo systemctl enable etcd2 flanneld docker kubelet",
            "until $(curl --output /dev/null --silent --head --fail http://127.0.0.1:8080); do sleep 2; done;",
            "curl -XPOST -H \"Content-Type: application/json\" -d '{\"apiVersion\":\"v1\", \"kind\": \"Namespace\", \"metadata\": {\"name\": \"kube-system\"}}' 'http://127.0.0.1:8080/api/v1/namespaces'"
          ]
          connection = {
            host = "${digitalocean_droplet.master.ipv4_address}"
            user = "core"
            agent = true
          }
      }

      depends_on=["null_resource.keys"]
}

resource "null_resource" "minion_provisioning" {

      count = "${var.minion_count}"

      provisioner "file" {
          source = "./keys/"
          destination = "/etc/kubernetes/ssl/"
          connection = {
            host = "${element(digitalocean_droplet.minion.*.ipv4_address, count.index)}"
            user = "core"
            agent = true
          }
      }

      provisioner "remote-exec" {
        inline = [
            "cat << EOF > /etc/flannel/options.env",
            "${element(template_file.flannel_opts_minion.*.rendered, count.index)}",
            "EOF",

            "cat << EOF > /etc/kubernetes/worker-kubeconfig.yaml",
            "${template_file.worker_kubeconfig.rendered}",
            "EOF",

            "cat << EOF > /etc/kubernetes/manifests/kube-proxy.yaml",
            "${template_file.minion_proxy.rendered}",
            "EOF",

            "cat << EOF > /etc/systemd/system/kubelet.service",
            "${element(template_file.minion_kubelet.*.rendered, count.index)}",
            "EOF",

            "sudo systemctl daemon-reload",
            "sudo systemctl start etcd2",
            "sudo systemctl start flanneld",
            "sudo systemctl start docker",
            "sudo systemctl start kubelet",
            "sudo systemctl enable etcd2 flanneld docker kubelet"
          ]
          connection = {
            host = "${element(digitalocean_droplet.minion.*.ipv4_address, count.index)}"
            user = "core"
            agent = true
          }
      }

      depends_on = ["null_resource.master_provisioning", "null_resource.keys"]
}



resource "digitalocean_droplet" "master" {
    image = "${var.os}"
    name = "${var.prefix}-master"
    region = "${var.region}"
    size = "${var.master_size}"
    user_data = "${template_file.cloud_config.rendered}"
    ssh_keys = ["${digitalocean_ssh_key.default.id}"]
    private_networking = true

    provisioner "remote-exec" {
        inline = [
            "sudo mkdir -p /etc/systemd/system/",
            "sudo mkdir -p /etc/kubernetes/ssl",
            "sudo mkdir -p /etc/kubernetes/manifests",
            "sudo mkdir -p /etc/flannel",
            "sudo mkdir -p /srv/kubernetes/manifests",
            "sudo mkdir -p /etc/systemd/system/docker.service.d",
            "sudo mkdir -p /etc/systemd/system/flanneld.service.d",
            "sudo chown -R core:core /etc/kubernetes",
            "sudo chown -R core:core /etc/systemd/system/",
            "sudo chown -R core:core /etc/flannel",
            "sudo chown -R core:core /srv/kubernetes"
        ]
        connection = {
          user = "core"
          agent = true
        }
    }

    provisioner "file" {
        source = "./common/systemd/flannel-before-docker.conf"
        destination = "/etc/systemd/system/docker.service.d/40-flannel.conf"
        connection = {
          user = "core"
          agent = true
        }
    }

    provisioner "file" {
        source = "./common/systemd/flannel-runtime.conf"
        destination = "/etc/systemd/system/flanneld.service.d/40-ExecStartPre-symlink.conf"
        connection = {
          user = "core"
          agent = true
        }
    }
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

  provisioner "remote-exec" {
      inline = [
      "sudo mkdir -p /etc/systemd/system/",
      "sudo mkdir -p /etc/kubernetes/ssl",
      "sudo mkdir -p /etc/kubernetes/manifests",
      "sudo mkdir -p /etc/flannel",
      "sudo mkdir -p /srv/kubernetes/manifests",
      "sudo mkdir -p /etc/systemd/system/docker.service.d",
      "sudo mkdir -p /etc/systemd/system/flanneld.service.d",
      "sudo chown -R core:core /etc/kubernetes",
      "sudo chown -R core:core /etc/systemd/system/",
      "sudo chown -R core:core /etc/flannel",
      "sudo chown -R core:core /srv/kubernetes"
      ]
      connection = {
        user = "core"
        agent = true
      }
  }

  provisioner "file" {
      source = "./common/systemd/flannel-before-docker.conf"
      destination = "/etc/systemd/system/docker.service.d/40-flannel.conf"
      connection = {
        user = "core"
        agent = true
      }
  }

  provisioner "file" {
      source = "./common/systemd/flannel-runtime.conf"
      destination = "/etc/systemd/system/flanneld.service.d/40-ExecStartPre-symlink.conf"
      connection = {
        user = "core"
        agent = true
      }
  }

}
