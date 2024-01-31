# Docker Container Service

Terraform module which deploys container service on Docker.

## Usage

```hcl
module "example" {
  source = "..."

  infrastructure = {
    network_id = "..."
  }

  containers = [
    {
      image     = "nginx:alpine"
      resources = {
        cpu    = 0.1
        memory = 100                 # in megabyte
      }
      ports = [
        {
          internal = 80
          external = 80
        }
      ]
      checks = [
        {
          delay = 10
          type  = "http"
          http = {
            port = 80
          }
        }
      ]
    }
  ]
}
```

## Examples

- [Complete](./examples/complete)
- [Grafana](./examples/grafana)
- [Nginx](./examples/nginx)
- [Walrus](./examples/walrus)
- [WordPress](./examples/wordpress)

## Contributing

Please read our [contributing guide](./docs/CONTRIBUTING.md) if you're interested in contributing to Walrus template.

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.0 |
| <a name="requirement_docker"></a> [docker](#requirement\_docker) | >= 3.0.2 |
| <a name="requirement_local"></a> [local](#requirement\_local) | >= 2.4.0 |
| <a name="requirement_random"></a> [random](#requirement\_random) | >= 3.5.1 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_docker"></a> [docker](#provider\_docker) | >= 3.0.2 |
| <a name="provider_local"></a> [local](#provider\_local) | >= 2.4.0 |
| <a name="provider_random"></a> [random](#provider\_random) | >= 3.5.1 |
| <a name="provider_terraform"></a> [terraform](#provider\_terraform) | n/a |

## Modules

No modules.

## Resources

| Name | Type |
|------|------|
| [docker_container.inits](https://registry.terraform.io/providers/kreuzwerker/docker/latest/docs/resources/container) | resource |
| [docker_container.pause](https://registry.terraform.io/providers/kreuzwerker/docker/latest/docs/resources/container) | resource |
| [docker_container.runs](https://registry.terraform.io/providers/kreuzwerker/docker/latest/docs/resources/container) | resource |
| [docker_container.unhealthy_restart](https://registry.terraform.io/providers/kreuzwerker/docker/latest/docs/resources/container) | resource |
| [docker_image.inits](https://registry.terraform.io/providers/kreuzwerker/docker/latest/docs/resources/image) | resource |
| [docker_image.pause](https://registry.terraform.io/providers/kreuzwerker/docker/latest/docs/resources/image) | resource |
| [docker_image.runs](https://registry.terraform.io/providers/kreuzwerker/docker/latest/docs/resources/image) | resource |
| [docker_image.unhealthy_restart](https://registry.terraform.io/providers/kreuzwerker/docker/latest/docs/resources/image) | resource |
| [docker_volume.ephemeral_volumes](https://registry.terraform.io/providers/kreuzwerker/docker/latest/docs/resources/volume) | resource |
| [local_file.ephemeral_files](https://registry.terraform.io/providers/hashicorp/local/latest/docs/resources/file) | resource |
| [random_string.name_suffix](https://registry.terraform.io/providers/hashicorp/random/latest/docs/resources/string) | resource |
| [terraform_data.run_checks](https://registry.terraform.io/providers/hashicorp/terraform/latest/docs/resources/data) | resource |
| [terraform_data.run_executes](https://registry.terraform.io/providers/hashicorp/terraform/latest/docs/resources/data) | resource |
| [terraform_data.run_resources](https://registry.terraform.io/providers/hashicorp/terraform/latest/docs/resources/data) | resource |
| [docker_network.network](https://registry.terraform.io/providers/kreuzwerker/docker/latest/docs/data-sources/network) | data source |
| [docker_registry_image.inits](https://registry.terraform.io/providers/kreuzwerker/docker/latest/docs/data-sources/registry_image) | data source |
| [docker_registry_image.pause](https://registry.terraform.io/providers/kreuzwerker/docker/latest/docs/data-sources/registry_image) | data source |
| [docker_registry_image.runs](https://registry.terraform.io/providers/kreuzwerker/docker/latest/docs/data-sources/registry_image) | data source |
| [docker_registry_image.unhealthy_restart](https://registry.terraform.io/providers/kreuzwerker/docker/latest/docs/data-sources/registry_image) | data source |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_containers"></a> [containers](#input\_containers) | Specify the container items to deploy.<br><br>Examples:<pre>containers:<br>- profile: init/run<br>  image: string<br>  execute:<br>    working_dir: string, optional<br>    command: list(string), optional<br>    args: list(string), optional<br>    readonly_rootfs: bool, optional<br>    as_user: number, optional<br>    as_group: number, optional<br>    privileged: bool, optional<br>  resources:<br>    cpu: number, optional               # in oneCPU, i.e. 0.25, 0.5, 1, 2, 4<br>    memory: number, optional            # in megabyte<br>    gpu: number, optional               # in oneGPU, i.e. 1, 2, 4<br>  envs:<br>  - name: string<br>    value: string, optional<br>    value_refer:<br>      schema: string<br>      params: map(any)<br>  files:<br>  - path: string<br>    mode: string, optional<br>    accept_changed: bool, optional      # accpet changed<br>    content: string, optional<br>    content_refer:<br>      schema: string<br>      params: map(any)<br>  mounts:<br>  - path: string<br>    readonly: bool, optional<br>    subpath: string, optional<br>    volume: string, optional            # shared between containers if named, otherwise exclusively by this container<br>    volume_refer:<br>      schema: string<br>      params: map(any)<br>  ports:<br>  - internal: number<br>    external: number, optional<br>    protocol: tcp/udp<br>    schema: string, optional<br>  checks:                               # maximum 1 check<br>  - type: execute/tcp/http/https<br>    delay: number, optional<br>    interval: number, optional<br>    timeout: number, optional<br>    retries: number, optional<br>    teardown: bool, optional<br>    execute:<br>      command: list(string)<br>    tcp:<br>      port: number<br>    http:<br>      port: number<br>      headers: map(string), optional<br>      path: string, optional<br>    https:<br>      port: number<br>      headers: map(string), optional<br>      path: string, optional</pre> | <pre>list(object({<br>    profile = optional(string, "run")<br>    image   = string<br>    execute = optional(object({<br>      working_dir     = optional(string)<br>      command         = optional(list(string))<br>      args            = optional(list(string))<br>      readonly_rootfs = optional(bool, false)<br>      as_user         = optional(number)<br>      as_group        = optional(number)<br>      privileged      = optional(bool, false)<br>    }))<br>    resources = optional(object({<br>      cpu    = optional(number, 0.25)<br>      memory = optional(number, 256)<br>      gpu    = optional(number, 0)<br>    }))<br>    envs = optional(list(object({<br>      name  = string<br>      value = optional(string)<br>      value_refer = optional(object({<br>        schema = string<br>        params = map(any)<br>      }))<br>    })))<br>    files = optional(list(object({<br>      path           = string<br>      mode           = optional(string, "0644")<br>      accept_changed = optional(bool, false)<br>      content        = optional(string)<br>      content_refer = optional(object({<br>        schema = string<br>        params = map(any)<br>      }))<br>    })))<br>    mounts = optional(list(object({<br>      path     = string<br>      readonly = optional(bool, false)<br>      subpath  = optional(string)<br>      volume   = optional(string)<br>      volume_refer = optional(object({<br>        schema = string<br>        params = map(any)<br>      }))<br>    })))<br>    ports = optional(list(object({<br>      internal = number<br>      external = optional(number)<br>      protocol = optional(string, "tcp")<br>      schema   = optional(string)<br>    })))<br>    checks = optional(list(object({<br>      type     = string<br>      delay    = optional(number, 0)<br>      interval = optional(number, 10)<br>      timeout  = optional(number, 1)<br>      retries  = optional(number, 1)<br>      teardown = optional(bool, false)<br>      execute = optional(object({<br>        command = list(string)<br>      }))<br>      tcp = optional(object({<br>        port = number<br>      }))<br>      http = optional(object({<br>        port    = number<br>        headers = optional(map(string))<br>        path    = optional(string, "/")<br>      }))<br>      https = optional(object({<br>        port    = number<br>        headers = optional(map(string))<br>        path    = optional(string, "/")<br>      }))<br>    })))<br>  }))</pre> | n/a | yes |
| <a name="input_context"></a> [context](#input\_context) | Receive contextual information. When Walrus deploys, Walrus will inject specific contextual information into this field.<br><br>Examples:<pre>context:<br>  project:<br>    name: string<br>    id: string<br>  environment:<br>    name: string<br>    id: string<br>  resource:<br>    name: string<br>    id: string</pre> | `map(any)` | `{}` | no |
| <a name="input_deployment"></a> [deployment](#input\_deployment) | Specify the deployment action.<br><br>Examples:<pre>deployment:<br>  fs_group: number, optional<br>  sysctls:<br>  - name: string<br>    value: string</pre> | <pre>object({<br>    fs_group = optional(number)<br>    sysctls = optional(list(object({<br>      name  = string<br>      value = string<br>    })))<br>  })</pre> | `{}` | no |
| <a name="input_infrastructure"></a> [infrastructure](#input\_infrastructure) | Specify the infrastructure information for deploying.<br><br>Examples:<pre>infrastructure:<br>  network_id: string, optional<br>  domain_suffix: string, optional<br>  pause_image: string, optional              # keep worker containers crashing or restarting without losing the network.<br>  unhealthy_restart_image: string, optional  # restart the unhealthy containers, https://github.com/moby/moby/pull/22719.</pre> | <pre>object({<br>    network_id              = optional(string, "local-walrus")<br>    domain_suffix           = optional(string, "cluster.local")<br>    pause_image             = optional(string, "docker/desktop-kubernetes-pause:3.9")<br>    unhealthy_restart_image = optional(string, "willfarrell/autoheal:latest")<br>  })</pre> | <pre>{<br>  "domain_suffix": "cluster.local",<br>  "network_id": "local-walrus",<br>  "pause_image": "docker/desktop-kubernetes-pause:3.9",<br>  "unhealthy_restart_image": "willfarrell/autoheal:latest"<br>}</pre> | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_address"></a> [address](#output\_address) | The address, a string only has host, might be a comma separated string or a single string. |
| <a name="output_connection"></a> [connection](#output\_connection) | The connection, a string combined host and port, might be a comma separated string or a single string. |
| <a name="output_context"></a> [context](#output\_context) | The input context, a map, which is used for orchestration. |
| <a name="output_endpoints"></a> [endpoints](#output\_endpoints) | The endpoints, a string map, the key is the name, and the value is the URL. |
| <a name="output_ports"></a> [ports](#output\_ports) | The port list of the service. |
| <a name="output_refer"></a> [refer](#output\_refer) | The refer, a map, including hosts, ports and account, which is used for dependencies or collaborations. |
<!-- END_TF_DOCS -->

## License

Copyright (c) 2023 [Seal, Inc.](https://seal.io)

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at [LICENSE](./LICENSE) file for details.

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
