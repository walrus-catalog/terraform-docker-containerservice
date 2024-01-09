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

module "this" {
  source = "../.."

  infrastructure = {
    network_id = "bridge" # docker0
  }

  deployment = {
    sysctls = [
      {
        name  = "net.ipv4.tcp_syncookies"
        value = sensitive("1") # sensitive value
      }
    ]
  }

  containers = [
    #
    # Init Container
    #
    {
      profile = sensitive("init")
      image   = "busybox"
      execute = {
        command = [
          "sh",
          sensitive("-c"),
          "cp /var/run/dir1/logs.txt /var/run/dir2/; cat /var/run/dir2/logs.txt"
        ]
      }
      envs = [
        {
          name  = sensitive("ENV1") # sensitive value
          value = "VALUE1"
        }
      ]
      resources = {
        cpu    = sensitive(0.1) # sensitive value
        memory = 100
      }
      files = [
        {
          path    = sensitive("/var/run/dir1/logs.txt") # sensitive value
          content = "Hello"
        }
      ]
      mounts = [
        {
          path   = "/var/run/dir2"
          volume = sensitive("data2") # sensitive value
        }
      ]
    },
    #
    # Run Container
    #
    {
      image = sensitive("nginx:alpine") # sensitive value
      resources = {
        cpu    = 0.1
        memory = sensitive(100) # sensitive value
      }
      envs = [
        {
          name  = "ENV1"
          value = sensitive("VALUE1") # sensitive value
        }
      ]
      files = [
        {
          path    = "/usr/share/nginx/html/index.html"
          content = sensitive("<html><h1>Hello</h1></html") # sensitive value
        }
      ]
      mounts = [
        {
          path = sensitive("/var/run/dir1") # sensitive value
        },
        {
          path   = "/var/run/dir2"
          volume = "data2"
        }
      ]
      ports = [
        {
          internal = sensitive(443)     # sensitive value
          external = sensitive(8443)    # sensitive value
          protocol = sensitive("tcp")   # sensitive value
          schema   = sensitive("https") # sensitive value
        }
      ]
      checks = [
        {
          type  = "http"
          delay = sensitive(10) # sensitive value
          http = {
            port = 80
            headers = {
              "X-Agent" = sensitive("localhost") # sensitive value
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
