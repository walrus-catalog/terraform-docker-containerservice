terraform {
  required_version = ">= 1.0"

  required_providers {
    random = {
      source  = "hashicorp/random"
      version = ">= 3.5.1"
    }
    local = {
      source  = "hashicorp/local"
      version = ">= 2.4.0"
    }
    docker = {
      source  = "kreuzwerker/docker"
      version = ">= 3.0.2"
    }
  }
}

provider "docker" {
}

resource "docker_network" "example" {
  name = "grafana-svc"

  attachable      = true
  check_duplicate = true
  driver          = "bridge"
  options = {
    "com.docker.network.bridge.enable_icc"           = "true"
    "com.docker.network.bridge.enable_ip_masquerade" = "true"
    "com.docker.network.bridge.host_binding_ipv4"    = "0.0.0.0"
    "com.docker.network.driver.mtu"                  = "65535"
  }
}

module "this" {
  source = "../.."

  infrastructure = {
    network_id = docker_network.example.id
  }

  containers = [
    {
      image = "grafana/grafana:latest"
      execute = {
        as_user = 472 # start as grafana user
      }
      resources = {
        cpu    = 1
        memory = 1024 # Mi
      }
      ports = [
        {
          internal = 3000
          external = 3000
        }
      ]
      checks = [
        {
          type     = "http"
          delay    = 10
          teardown = true
          retries  = 3
          interval = 30
          timeout  = 2
          http = {
            port = 3000
            path = "/robots.txt"
          }
        },
        { # covered by the previous check.
          type     = "http"
          retries  = 3
          interval = 10
          timeout  = 1
          teardown = true
          http = {
            port = 3000
          }
        }
      ]
    }
  ]
}

output "context" {
  value = module.this.context
}

output "refer" {
  value = nonsensitive(module.this.refer)
}

output "connection" {
  value = module.this.connection
}

output "address" {
  value = module.this.address
}

output "ports" {
  value = module.this.ports
}

output "endpoints" {
  value = module.this.endpoints
}
