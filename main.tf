resource "scaleway_vpc_private_network" "pn" {
  name = "private"
}

resource "scaleway_vpc_public_gateway_ip" "gw_ip" {}

resource "scaleway_vpc_public_gateway_dhcp" "dhcp" {
  subnet               = "192.168.0.0/24"
  address              = "192.168.0.1"
  pool_low             = "192.168.0.2"
  pool_high            = "192.168.0.50"
  enable_dynamic       = true
  push_default_route   = true
  push_dns_server      = true
  dns_servers_override = ["192.168.0.1"]
  dns_local_name       = scaleway_vpc_private_network.pn.name
  depends_on           = [scaleway_vpc_private_network.pn]
}

resource "scaleway_vpc_public_gateway" "pgw" {
  name            = "gateway"
  type            = "VPC-GW-S"
  bastion_enabled = true
  ip_id           = scaleway_vpc_public_gateway_ip.gw_ip.id
  depends_on      = [scaleway_vpc_public_gateway_ip.gw_ip]
}

resource "scaleway_vpc_gateway_network" "vpc" {
  gateway_id         = scaleway_vpc_public_gateway.pgw.id
  private_network_id = scaleway_vpc_private_network.pn.id
  dhcp_id            = scaleway_vpc_public_gateway_dhcp.dhcp.id
  cleanup_dhcp       = true
  enable_masquerade  = true
  depends_on         = [scaleway_vpc_public_gateway.pgw, scaleway_vpc_private_network.pn, scaleway_vpc_public_gateway_dhcp.dhcp, scaleway_instance_server.srv]
}

resource "scaleway_instance_server" "srv" {
  count = var.scale
  name  = format("srv-%d", count.index)
  image = "ubuntu_jammy"
  type  = "DEV1-S"

  private_network {
    pn_id = scaleway_vpc_private_network.pn.id
  }

  user_data = {
    cloud-init = <<-EOT
    #cloud-config
    runcmd:
      - apt-get update
      - apt-get install nginx -y
      - systemctl enable --now nginx
      - hostnamectl hostname ${format("srv-%d.%s", count.index, scaleway_vpc_private_network.pn.name)}
      - echo "Hello i'm $(hostname)!" > /var/www/html/index.nginx-debian.html
      - reboot # Make sure static DHCP reservation catch up
    EOT
  }

}

resource "scaleway_vpc_public_gateway_dhcp_reservation" "app" {
  count              = var.scale
  gateway_network_id = scaleway_vpc_gateway_network.vpc.id
  mac_address        = scaleway_instance_server.srv[count.index].private_network.0.mac_address
  ip_address         = format("192.168.0.%d", (60 + count.index))
  depends_on         = [scaleway_instance_server.srv]
}

resource "scaleway_lb_ip" "lb_ip" {}

resource "scaleway_lb" "lb" {
  name  = "loadbalancer"
  ip_id = scaleway_lb_ip.lb_ip.id
  type  = "LB-S"
  private_network {
    private_network_id = scaleway_vpc_private_network.pn.id
    dhcp_config        = true
  }
}

resource "scaleway_lb_backend" "backend" {
  name             = "backend-app"
  lb_id            = scaleway_lb.lb.id
  forward_protocol = "tcp"
  forward_port     = 80
  server_ips       = scaleway_vpc_public_gateway_dhcp_reservation.app.*.ip_address

  health_check_tcp {}
}

resource "scaleway_lb_certificate" "cert" {
  lb_id = scaleway_lb.lb.id
  name  = "certificate"

  letsencrypt {
    common_name = format("app.%s.lb.%s.scw.cloud", replace(scaleway_lb_ip.lb_ip.ip_address, ".", "-"), scaleway_lb.lb.region)
  }
}

resource "scaleway_lb_frontend" "frontend" {
  name            = "frontend-https"
  lb_id           = scaleway_lb.lb.id
  backend_id      = scaleway_lb_backend.backend.id
  inbound_port    = 443
  certificate_ids = [scaleway_lb_certificate.cert.id]
}
