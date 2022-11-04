output "ssh-access" {
  value = formatlist("ssh -J bastion@%s:61000 root@%s.%s", resource.scaleway_vpc_public_gateway_ip.gw_ip.address, scaleway_instance_server.srv.*.name, scaleway_vpc_private_network.pn.name)
}

output "http-access" {
  value = format("https://app.%s.lb.%s.scw.cloud", replace(scaleway_lb_ip.lb_ip.ip_address, ".", "-"), scaleway_lb.lb.region)
}


