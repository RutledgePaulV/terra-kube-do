#!/bin/bash
kubectl config set-cluster ${cluster_name} --server=https://${master_ip} --certificate-authority=${ca_cert} --embed-certs=true
kubectl config set-credentials ${cluster_user} --certificate-authority=${ca_cert} --client-key=${admin_key} --client-certificate=${admin_cert} --embed-certs=true
kubectl config set-context ${context_name} --cluster=${cluster_name} --user=${cluster_user}
