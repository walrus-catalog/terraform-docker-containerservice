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
  name = "complete-svc"

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

resource "local_file" "example" {
  filename = "${path.module}/.cache/config.txt"
  content  = "this is config"
}

resource "local_sensitive_file" "example" {
  filename = "${path.module}/.cache/secret.txt"
  content  = "this is secret"
}

resource "docker_volume" "example" {
  name   = "example"
  driver = "local"
}

module "this" {
  source = "../.."

  infrastructure = {
    network_id  = docker_network.example.id
    pause_image = "busybox"
  }

  containers = [
    #
    # Init Container
    #
    {
      profile = "init"
      image   = "alpine"
      execute = {
        working_dir = "/"
        command = [
          "sh",
          "-c",
          "echo \"$${ENV1}:$${ENV2}:$${WALRUS_PROJECT_NAME}\" >> /var/run/dir2/logs.txt; cat /var/run/dir2/logs.txt"
        ]
      }
      envs = [
        {
          name  = "ENV1"
          value = "env1" # accpet changed and restart
        },
        {
          name = "ENV2"
          value_refer = { # donot accpet changed
            schema = "docker:localenv"
            params = {
              name = "example"
            }
          }
        },
        { # invalid
          name = "ENV3"
        },
        { # invalid
          name  = "ENV4"
          value = ""
          value_refer = {
            schema = "docker:localenv"
            params = {
              name = "example"
            }
          }
        },
        { # invalid schema
          name = "ENV5"
          value_refer = {
            schema = "localenv"
            params = {
              name = "example"
            }
          }
        },
        { # invalid params
          name = "ENV6"
          value_refer = {
            schema = "docker:localenv"
            params = {
              key = "example"
            }
          }
        },
        { # invalid, override by default
          name  = "WALRUS_PROJECT_NAME"
          value = "complete"
        }
      ]
      files = [
        { # ephemeral
          path           = "/var/run/config/file1"
          accept_changed = true
          content        = "this is ephemeral file"
        },
        { # refer
          path           = "/var/run/config-refer/file2"
          accept_changed = false
          content_refer = {
            schema = "docker:localfile"
            params = {
              path = local_sensitive_file.example.filename
            }
          }
        },
        { # invalid
          path = "/var/run/config/file3"
        },
        { # invalid
          path    = "/var/run/config/file4"
          content = "this is ephemeral file"
          content_refer = {
            schema = "docker:localfile"
            params = {
              path = local_file.example.filename
            }
          }
        },
        { # invalid schema
          path = "/var/run/config/file5"
          content_refer = {
            schema = "localfile"
            params = {
              path = local_file.example.filename
            }
          }
        },
        { # invalid params
          path = "/var/run/config/file6"
          content_refer = {
            schema = "docker:localfile"
            params = {
              name = local_file.example.filename
            }
          }
        }
      ]
      mounts = [
        {                        # ephemeral
          path = "/var/run/dir1" # exclusively by this container
        },
        { # ephemeral
          path   = "/var/run/dir2"
          volume = "data" # shared between containers
        },
        { # refer
          path = "/var/run/dir3"
          volume_refer = {
            schema = "docker:localvolumeclaim"
            params = {
              name = docker_volume.example.name
            }
          }
        },
        { # invalid
          path   = "/var/run/dir4"
          volume = "data"
          volume_refer = {
            schema = "docker:localvolumeclaim"
            params = {
              name = docker_volume.example.name
            }
          }
        },
        { # invalid schema
          path = "/var/run/dir5"
          volume_refer = {
            schema = "localvolumeclaim"
            params = {
              name = "example"
            }
          }
        },
      ]
    },

    #
    # Run Container
    #
    {
      image = "nginx:alpine"
      resources = {
        cpu    = 1
        memory = 1024 # Mi
      }
      files = [
        {
          path    = "/usr/share/nginx/html/index.html"
          content = <<-EOF
<html>
  <h1>Hi</h1>
  </br>
  <h1>This is first running nginx.</h1>
</html>
EOF
        }
      ]
      ports = [
        {
          internal = 80
          protocol = "UDP"
        },
        { # override the previous one
          internal = 80
          protocol = "TCP"
        },
        {
          internal = 8080
          protocol = "TCP"
        }
      ]
      checks = [
        {
          type     = "tcp"
          delay    = 10
          teardown = true
          tcp = {
            port = 80
          }
        },
        { # covered by the previous check.
          type = "http"
          http = {
            port = 80
          }
        },
        null
      ]
    },
    {
      image = "nginx"
      envs = [
        {
          name  = "NGINX_PORT"
          value = "8080"
        },
        null
      ]
      files = [
        {
          path           = "/usr/share/nginx/html/index.html"
          accept_changed = true
          content        = <<-EOF
<html>
  <h1>Hi</h1>
  </br>
  <h1>This is second running nginx.</h1>
</html>
EOF
        },
        {
          path           = "/etc/nginx/templates/default.conf.template"
          accept_changed = false
          content        = <<-EOF
server {
  listen       $${NGINX_PORT};
  server_name  localhost;
  location / {
      root   /usr/share/nginx/html;
      index  index.html index.htm;
  }
  location = /50x.html {
      root   /usr/share/nginx/html;
  }
}
EOF
        },
        null
      ]
      mounts = [
        { # ephemeral
          path   = "/test"
          volume = "data" # shared between containers
        },
        { # refer
          path = "/pvc"
          volume_refer = {
            schema = "docker:localvolumeclaim"
            params = {
              name = docker_volume.example.name
            }
          }
        },
        null
      ]
      ports = [
        { # override the previous container's specification
          internal = 8080
          external = 80 # expose
          protocol = "TCP"
        },
        null
      ]
    },
    null
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
