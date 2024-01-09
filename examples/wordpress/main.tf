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
  name = "wordpress-svc"

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

resource "docker_volume" "example" {
  name   = "example"
  driver = "local"
}

locals {
  volume_refer_database_data = {
    schema = "docker:localvolumeclaim"
    params = {
      name = docker_volume.example.name
    }
  }

  database = "wordpress"
  username = "myuser"
  password = "mypass"
}

module "this" {
  source = "../.."

  infrastructure = {
    network_id = docker_network.example.id
  }

  containers = [
    {
      image = "mysql:8.0"
      envs = [
        {
          name  = "MYSQL_DATABASE"
          value = local.database
        },
        {
          name  = "MYSQL_USER"
          value = local.username
        },
        {
          name  = "MYSQL_PASSWORD"
          value = local.password
        },
        {
          name  = "MYSQL_ROOT_PASSWORD"
          value = local.password
        }
      ]
      mounts = [
        {
          path         = "/var/lib/mysql"
          volume_refer = local.volume_refer_database_data # persistent
        }
      ]
      ports = [
        {
          internal = 3306
        }
      ]
      checks = [
        {
          type     = "tcp"
          delay    = 10
          teardown = true
          retries  = 3
          interval = 30
          timeout  = 2
          tcp = {
            port = 3306
          }
        }
      ]
    },

    {
      image = "wordpress:6.3.2-apache"
      envs = [
        {
          name  = "WORDPRESS_DB_HOST"
          value = "127.0.0.1:3306"
        },
        {
          name  = "WORDPRESS_DB_NAME"
          value = local.database
        },
        {
          name  = "WORDPRESS_DB_USER"
          value = local.username
        },
        {
          name  = "WORDPRESS_DB_PASSWORD"
          value = local.password
        }
      ]
      mounts = [
        {
          path = "/var/www/html" # ephemeral
        }
      ]
      ports = [
        {
          internal = 80
          external = 80 # publish
          protocol = "tcp"
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
            port = 80
            path = "/"
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
