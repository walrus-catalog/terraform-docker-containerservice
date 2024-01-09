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
  name = "nginx-svc"

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

  deployment = {
    sysctls = [
      {
        name  = "net.ipv4.tcp_syncookies"
        value = "1"
      }
    ]
  }

  containers = [
    {
      image = "nginx:alpine"
      resources = {
        cpu    = 0.1
        memory = 100 # Mi
      }
      files = [
        {
          path    = "/usr/share/nginx/html/index.html"
          content = <<-EOF
<html>
  <h1>Hi</h1>
  </br>
  <h1>Welcome to Docker Container Service.</h1>
</html>
EOF
        },
        {
          path    = "/usr/share/nginx/html/again.html"
          content = <<-EOF
<html>
  <h1>Hi</h1>
  </br>
  <h1>Welcome to Docker Container Service Again.</h1>
</html>
EOF
        }
      ]
      ports = [
        {
          internal = 80
          external = 8080 # publish
          protocol = "tcp"
        }
      ]
      checks = [
        {
          type     = "http"
          delay    = 10
          teardown = true
          http = {
            port = 80
            headers = {
              "X-Agent" = "localhost"
            }
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
