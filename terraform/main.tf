locals {
  network_name = "pg-lab-net"
  subnet_name  = "pg-lab-subnet"
  cidr_block   = "10.10.0.0/16"
}

resource "yandex_vpc_network" "this" {
  name = local.network_name
}

resource "yandex_vpc_subnet" "this" {
  name           = local.subnet_name
  zone           = var.zone
  network_id     = yandex_vpc_network.this.id
  v4_cidr_blocks = [local.cidr_block]
  route_table_id = yandex_vpc_route_table.private.id
}


## Routes
resource "yandex_vpc_gateway" "egress_gateway" {
  name      = "nat-gateway"
  shared_egress_gateway {}
}

resource "yandex_vpc_route_table" "private" {
  name       = "route-table-private"
  network_id = yandex_vpc_network.this.id

  static_route {
      destination_prefix = "0.0.0.0/0"
      gateway_id         = yandex_vpc_gateway.egress_gateway.id
    }
}




module "kube" {
  source = "git::https://github.com/terraform-yc-modules/terraform-yc-kubernetes.git?ref=1.1.2"
  cluster_name = "tsy-cluster"
  network_id = yandex_vpc_network.this.id
  enable_oslogin_or_ssh_keys = {
    enable-oslogin = "true"
    ssh-keys = null
  }

  master_locations = [
    {
      zone      = "ru-central1-a"
      subnet_id = yandex_vpc_subnet.this.id
    }
  ]

  master_maintenance_windows = [
    {
      day        = "monday"
      start_time = "20:00"
      duration   = "3h"
    }
  ]

  node_groups = {
    "yc-k8s-ng-01" = {
      description = "Kubernetes nodes group 01 with auto scaling"
      node_cores      = 4
      node_memory     = 4      
      nat             = "true"

      node_locations   = [
        {
          zone      = "ru-central1-a"
          subnet_id = yandex_vpc_subnet.this.id
        }
      ]      
      auto_scale = {
        min     = 2
        max     = 3
        initial = 2
      }
    }
  }
}
