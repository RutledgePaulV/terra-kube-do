#!/bin/bash
openssl genrsa -out ./keys/ca-key.pem 2048
openssl req -x509 -new -nodes -key ./keys/ca-key.pem -days 10000 -out ./keys/ca.pem -subj /CN=kube-ca
openssl genrsa -out ./keys/apiserver-key.pem 2048
openssl req -new -key ./keys/apiserver-key.pem -out apiserver.csr -subj /CN=kube-apiserver -config ./keys/openssl.conf
openssl x509 -req -in ./keys/apiserver.csr -CA ./keys/ca.pem -CAkey ./keys/ca-key.pem -CAcreateserial -out ./keys/apiserver.pem -days 365 -extensions v3_req -extfile ./keys/openssl.conf
openssl genrsa -out ./keys/worker-key.pem 2048
openssl req -new -key ./keys/worker-key.pem -out ./keys/worker.csr -subj /CN=kube-worker
openssl x509 -req -in ./keys/worker.csr -CA ./keys/ca.pem -CAkey ./keys/ca-key.pem -CAcreateserial -out ./keys/worker.pem -days 365
openssl genrsa -out ./keys/admin-key.pem 2048
openssl req -new -key ./keys/admin-key.pem -out ./keys/admin.csr -subj /CN=kube-admin
openssl x509 -req -in ./keys/admin.csr -CA ./keys/ca.pem -CAkey ./keys/ca-key.pem -CAcreateserial -out ./keys/admin.pem -days 365
