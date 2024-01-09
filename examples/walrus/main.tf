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

locals {
  database = "walrus"
  username = "root"
  password = "Root123"
}

module "postgres" {
  source = "../.."

  context = {
    resource = {
      name = "postgres"
    }
  }

  infrastructure = {
    network_id = docker_network.example.id
  }

  containers = [
    {
      image = "postgres:14.8"
      execute = {
        privileged = true
      }
      resources = {
        cpu    = 1
        memory = 4096 # mb
      }
      envs = [
        {
          name  = "POSTGRES_USER"
          value = local.username
        },
        {
          name  = "POSTGRES_PASSWORD"
          value = local.password
        },
        {
          name  = "POSTGRES_DB"
          value = local.database
        }
      ]
      files = [
        {
          path    = "/scripts/probe.sh",
          mode    = "0744",
          content = <<EOF
#!/usr/bin/env bash

set -o errexit
set -o nounset
set -o pipefail

psql --no-password --username=$${POSTGRES_USER} --dbname=$${POSTGRES_DB} --command="SELECT 1"
EOF
        }
      ]
      mounts = [
        {
          volume = "postgres-data"
          path   = "/var/lib/postgresql/data"
        }
      ]
      ports = [
        {
          internal = 5432
          external = 5432
          protocol = "tcp"
        }
      ]
      checks = [
        {
          type     = "execute"
          teardown = true
          interval = 10
          timeout  = 5
          retries  = 3
          execute = {
            command = [
              "sh",
              "-c",
              "/scripts/probe.sh"
            ]
          }
        }
      ]
    }
  ]
}

output "endpoints_postgres" {
  value = module.postgres.endpoints
}

module "casdoor" {
  source = "../.."

  context = {
    resource = {
      name = "casdoor"
    }
  }

  infrastructure = {
    network_id = docker_network.example.id
  }

  containers = [
    {
      profile = "init"
      image   = "sealio/casdoor:v1.344.0-seal.1"
      execute = {
        working_dir = "/tmp/conf"
        command = [
          "/scripts/init.sh"
        ]
      }
      envs = [
        {
          name  = "DB_DRIVER"
          value = "postgres"
        },
        {
          name  = "DB_USER"
          value = local.username
        },
        {
          name  = "DB_PASSWORD"
          value = local.password
        },
        {
          name  = "DB_NAME"
          value = local.database
        },
        {
          name  = "DB_SOURCE"
          value = "postgres://${local.username}:${local.password}@${module.postgres.address}:5432/${local.database}?sslmode=disable"
        }
      ]
      files = [
        {
          path    = "/scripts/init.sh"
          mode    = "0744"
          content = <<EOF
#!/usr/bin/env bash

set -o errexit
set -o nounset
set -o pipefail

# validate database
set +o errexit
while true; do
  if psql --command="SELECT 1" "$${DB_SOURCE}" >/dev/null 2>&1; then
    break
  fi
  echo "waiting db to be ready ..."
  sleep 2s
done
set -o errexit

# mutate app configuration
cp -f /conf/app.conf app.conf
sed -i '/^tableNamePrefix =.*/d' app.conf
echo "tableNamePrefix = casdoor_" >>app.conf
sed -i '/^driverName =.*/d' app.conf
echo "driverName = \"$${DB_DRIVER}\"" >>app.conf
sed -i '/^dataSourceName =.*/d' app.conf
echo "dataSourceName = \"$${DB_SOURCE}\"" >>app.conf
sed -i '/^sessionConfig =.*/d' app.conf
echo 'sessionConfig = {"enableSetCookie":true,"cookieName":"casdoor_session_id","cookieLifeTime":3600,"providerConfig":"/var/run/casdoor","gclifetime":3600,"domain":"","secure":false,"disableHTTPOnly":false}' >>app.conf
sed "s#$${DB_PASSWORD}#***#g" app.conf
EOF
        }
      ]
      mounts = [
        {
          volume = "conf"
          path   = "/tmp/conf"
        }
      ]
    },
    {
      image = "sealio/casdoor:v1.344.0-seal.1"
      execute = {
        privileged = true
      }
      ports = [
        {
          internal = 8000
          external = 8000
          protocol = "tcp"
        }
      ]
      # checks = [
      #   {
      #     type     = "tcp"
      #     teardown = true
      #     interval = 10
      #     timeout  = 5
      #     retries  = 3
      #     tcp = {
      #       port = 8000
      #     }
      #   }
      # ]
      mounts = [
        {
          volume = "conf"
          path   = "/conf"
        },
        {
          volume = "casdoor-data"
          path   = "/var/run/casdoor"
        }
      ]
    }
  ]
}

output "endpoints_casdoor" {
  value = module.casdoor.endpoints
}

module "redis" {
  source = "../.."

  context = {
    resource = {
      name = "redis"
    }
  }

  infrastructure = {
    network_id = docker_network.example.id
  }

  containers = [
    {
      image = "redis:6.2.11"
      execute = {
        command = [
          "redis-server",
          "--save",
          "\"\"",
          "--appendonly",
          "no",
          "--maxmemory",
          "1gb",
          "--maxmemory-policy",
          "allkeys-lru",
          "--requirepass",
          "Default123"
        ]
      }
      resources = {
        cpu    = 1
        memory = 1500 # mb
      }
      ports = [
        {
          internal = 6379
          external = 6379
          protocol = "tcp"
        }
      ]
    }
  ]
}

output "endpoints_redis" {
  value = module.redis.endpoints
}

module "walrus" {
  source = "../.."

  context = {
    resource = {
      name = "walrus"
    }
  }

  infrastructure = {
    network_id = docker_network.example.id
  }

  containers = [
    {
      image = "sealio/walrus:main"
      execute = {
        privileged = true
        command = [
          "walrus",
          "--log-debug",
          "--log-verbosity=4",
          "--data-source-address=postgres://${local.username}:${local.password}@${module.postgres.address}:5432/${local.database}?sslmode=disable",
          "--cache-source-address=redis://default:Default123@${module.redis.address}:6379/0",
          "--casdoor-server=http://${module.casdoor.address}:8000",
        ]
      }
      envs = [
        {
          name  = "K3S_RESOLV_CONF"
          value = ""
        }
      ]
      mounts = [
        {
          volume = "walrus-data"
          path   = "/var/run/walrus"
        }
      ]
      ports = [
        {
          internal = 80
          external = 80
          protocol = "tcp"
        },
        {
          internal = 443
          external = 443
          protocol = "tcp"
        }
      ]
      checks = [
        {
          type     = "https"
          teardown = true
          interval = 10
          timeout  = 5
          retries  = 10
          https = {
            port = 443
            path = "/livez"
          }
        }
      ]
    }
  ]
}

output "context" {
  value = module.walrus.context
}

output "refer" {
  value = nonsensitive(module.walrus.refer)
}

output "connection" {
  value = module.walrus.connection
}

output "address" {
  value = module.walrus.address
}

output "ports" {
  value = module.walrus.ports
}

output "endpoints" {
  value = module.walrus.endpoints
}
