#!/bin/bash
curl -X PUT -d 'value={"Network":"${pod_network_subnet}", "Backend": {"Type": "vxlan"}}' 'http://${master_private_ip}:2379/v2/keys/coreos.com/network/config'
