locals {
  project_name     = coalesce(try(var.context["project"]["name"], null), "default")
  project_id       = coalesce(try(var.context["project"]["id"], null), "default_id")
  environment_name = coalesce(try(var.context["environment"]["name"], null), "test")
  environment_id   = coalesce(try(var.context["environment"]["id"], null), "test_id")
  resource_name    = coalesce(try(var.context["resource"]["name"], null), "example")
  resource_id      = coalesce(try(var.context["resource"]["id"], null), "example_id")

  namespace     = join("-", [local.project_name, local.environment_name])
  domain_suffix = coalesce(var.infrastructure.domain_suffix, "cluster.local")
  network_id    = coalesce(var.infrastructure.network_id, "local-walrus")

  labels = {
    "walrus.seal.io/catalog-name"     = "terraform-docker-containerservice"
    "walrus.seal.io/project-id"       = local.project_id
    "walrus.seal.io/environment-id"   = local.environment_id
    "walrus.seal.io/resource-id"      = local.resource_id
    "walrus.seal.io/project-name"     = local.project_name
    "walrus.seal.io/environment-name" = local.environment_name
    "walrus.seal.io/resource-name"    = local.resource_name
  }
}

#
# Ensure
#

data "docker_network" "network" {
  name = local.network_id

  lifecycle {
    postcondition {
      condition     = self.driver == "bridge"
      error_message = "Docker network driver must be bridge"
    }
  }
}

#
# Parse
#

locals {
  wellknown_env_schemas    = [] # NB(thxCode): we don't support any wellknown env schemas yet.
  wellknown_file_schemas   = ["docker:localfile"]
  wellknown_mount_schemas  = ["docker:localvolumeclaim"]
  wellknown_port_protocols = ["TCP", "UDP"]

  internal_port_container_index_map = {
    for ip, cis in merge(flatten([
      for i, c in var.containers : [{
        for p in try(c.ports != null ? c.ports : [], []) : p.internal => i...
        if p != null
      }]
    ])...) : ip => cis[0]
  }

  containers = [
    for i, c in var.containers : merge(c, {
      name = format("%s-%d-%s", coalesce(c.profile, "run"), i, basename(split(":", c.image)[0]))
      envs = [
        for xe in [
          for e in(c.envs != null ? c.envs : []) : e
          if e != null && try(!(e.value != null && e.value_refer != null) && !(e.value == null && e.value_refer == null), false)
        ] : xe
        if xe.value_refer == null || (try(contains(local.wellknown_env_schemas, xe.value_refer.schema), false) && try(lookup(xe.value_refer.params, "name", null) != null, false))
      ]
      files = [
        for xf in [
          for f in(c.files != null ? c.files : []) : f
          if f != null && try(!(f.content != null && f.content_refer != null) && !(f.content == null && f.content_refer == null), false)
        ] : xf
        if xf.content_refer == null || (try(contains(local.wellknown_file_schemas, xf.content_refer.schema), false) && try(lookup(xf.content_refer.params, "path", null) != null, false))
      ]
      mounts = [
        for xm in [
          for m in(c.mounts != null ? c.mounts : []) : m
          if m != null && try(!(m.volume != null && m.volume_refer != null), false)
        ] : xm
        if xm.volume_refer == null || (try(contains(local.wellknown_mount_schemas, xm.volume_refer.schema), false) && try(lookup(xm.volume_refer.params, "name", null) != null, false))
      ]
      ports = [
        for xp in [
          for _, ps in {
            for p in(c.ports != null ? c.ports : []) : p.internal => {
              internal = p.internal
              external = p.external
              protocol = p.protocol == null ? "TCP" : upper(p.protocol)
              schema   = p.schema == null ? (contains([80, 8080], p.internal) ? "http" : (contains([443, 8443], p.internal) ? "https" : null)) : lower(p.schema)
            }...
            if p != null
          } : ps[length(ps) - 1]
          if local.internal_port_container_index_map[ps[length(ps) - 1].internal] == i
        ] : xp
        if try(contains(local.wellknown_port_protocols, xp.protocol), true)
      ]
      checks = [
        for ck in(c.checks != null ? c.checks : []) : ck
        if try(lookup(ck, ck.type, null) != null, false)
      ]
    })
    if c != null
  ]
}

locals {
  container_ephemeral_envs_map = {
    for c in local.containers : c.name => [
      for e in c.envs : e
      if try(e.value_refer == null, false)
    ]
    if c != null
  }
  container_refer_envs_map = {
    for c in local.containers : c.name => [
      for e in c.envs : e
      if try(e.value_refer != null, false)
    ]
    if c != null
  }

  container_ephemeral_files_map = {
    for c in local.containers : c.name => [
      for f in c.files : merge(f, {
        name = format("eph-f-%s-%s", c.name, md5(join("-", [local.project_name, local.environment_name, local.resource_name, f.path])))
      })
      if try(f.content_refer == null, false)
    ]
    if c != null
  }
  container_refer_files_map = {
    for c in local.containers : c.name => [
      for f in c.files : merge(f, {
        name = format("ref-f-%s-%s", c.name, md5(jsonencode(f.content_refer)))
      })
      if try(f.content_refer != null, false)
    ]
    if c != null
  }

  container_ephemeral_mounts_map = {
    for c in local.containers : c.name => [
      for m in c.mounts : merge(m, {
        name = format("eph-m-%s", try(m.volume == null || m.volume == "", true) ? md5(join("/", [c.name, m.path])) : md5(m.volume))
      })
      if try(m.volume_refer == null, false)
    ]
    if c != null
  }
  container_refer_mounts_map = {
    for c in local.containers : c.name => [
      for m in c.mounts : merge(m, {
        name = format("ref-m-%s", md5(jsonencode(m.volume_refer)))
      })
      if try(m.volume_refer != null, false)
    ]
    if c != null
  }

  init_containers = [
    for c in local.containers : c
    if c != null && try(c.profile == "init", false)
  ]
  run_containers = [
    for c in local.containers : c
    if c != null && try(c.profile == "" || c.profile == "run", true)
  ]
}

# create the name with a random suffix.

resource "random_string" "name_suffix" {
  length  = 10
  special = false
  upper   = false
}

locals {
  name     = join("-", [local.resource_name, random_string.name_suffix.result])
  fullname = join("-", [local.namespace, local.name])
}

#
# Deployment
#

## create ephemeral files.

locals {
  ephemeral_files = flatten([
    for _, fs in local.container_ephemeral_files_map : fs
  ])

  ephemeral_files_map = {
    for f in local.ephemeral_files : f.name => f
  }
}

resource "local_file" "ephemeral_files" {
  for_each = toset(keys(try(nonsensitive(local.ephemeral_files_map), local.ephemeral_files_map)))

  filename = abspath("${path.root}/.cache/${local.fullname}/${each.key}")
  content  = local.ephemeral_files_map[each.key].content
}

## create ephemeral volumes.

locals {
  ephemeral_mounts = [
    for _, v in {
      for m in flatten([
        for _, ms in local.container_ephemeral_mounts_map : ms
      ]) : m.name => m...
    } : v[0]
  ]

  ephemeral_mounts_map = {
    for m in local.ephemeral_mounts : m.name => m
  }
}

resource "docker_volume" "ephemeral_volumes" {
  for_each = toset(keys(try(nonsensitive(local.ephemeral_mounts_map), local.ephemeral_mounts_map)))

  name = join("-", [local.fullname, each.key])
  labels {
    label = "walrus.seal.io/volume-name"
    value = each.key
  }
  dynamic "labels" {
    for_each = local.labels
    content {
      label = labels.key
      value = labels.value
    }
  }

  driver = "local"
}

## create pause docker container.

data "docker_registry_image" "pause" {
  name = var.infrastructure.pause_image
}

resource "docker_image" "pause" {
  name = var.infrastructure.pause_image

  keep_locally  = true
  pull_triggers = [data.docker_registry_image.pause.sha256_digest]
}

locals {
  publish_ports = flatten([
    for c in local.containers : [
      for p in c.ports : p
      if try(p.external != null, false)
    ]
    if c != null
  ])
}

resource "docker_container" "pause" {
  name = join("-", [local.fullname, "pause"])
  labels {
    label = "walrus.seal.io/container-name"
    value = "pause"
  }
  dynamic "labels" {
    for_each = local.labels
    content {
      label = labels.key
      value = labels.value
    }
  }

  ### configure shared ipc.
  ipc_mode = "shareable"
  sysctls = try(var.deployment.sysctls != null, false) ? {
    for c in var.deployment.sysctls : c.name => c.value
  } : null
  ### configure shared network.
  hostname = local.name
  host {
    host = "host.docker.internal"
    ip   = "host-gateway"
  }
  networks_advanced {
    name = data.docker_network.network.id
    aliases = [
      join(".", [local.resource_name, local.namespace]),
      join(".", [local.resource_name, local.namespace, "svc"]),
      join(".", [local.resource_name, local.namespace, "svc", local.domain_suffix])
    ]
  }
  dynamic "ports" {
    for_each = try(nonsensitive(local.publish_ports), local.publish_ports)
    content {
      internal = ports.value.internal
      external = ports.value.external
      protocol = lower(ports.value.protocol)
    }
  }
  ### configure execute.
  image       = docker_image.pause.image_id
  restart     = "always"
  stdin_open  = anytrue([strcontains(docker_image.pause.name, "busybox"), strcontains(docker_image.pause.name, "alpine")])
  memory_swap = 0
}

## create unhealthy restart docker container.

locals {
  unhealthy_restart = try(length([
    for c in local.run_containers : c
    if try(length(c.checks) > 0 && c.checks[0].teardown, false)
  ]) > 0, false)
  unhealthy_restart_label = format("walrus.seal.io/healthcheck-%s", local.fullname)
}

data "docker_registry_image" "unhealthy_restart" {
  count = local.unhealthy_restart ? 1 : 0

  name = var.infrastructure.unhealthy_restart_image
}

resource "docker_image" "unhealthy_restart" {
  count = local.unhealthy_restart ? 1 : 0

  name = var.infrastructure.unhealthy_restart_image

  keep_locally  = true
  pull_triggers = [data.docker_registry_image.unhealthy_restart[0].sha256_digest]
}

resource "docker_container" "unhealthy_restart" {
  count = local.unhealthy_restart ? 1 : 0

  name = join("-", [local.fullname, "unhealthy-restart"])
  labels {
    label = "walrus.seal.io/container-name"
    value = "unhealthy-restart"
  }

  ### share from pause container.
  ipc_mode     = local.pause_container
  network_mode = local.pause_container

  ### configure execute.
  must_run = true
  restart  = "always"
  image    = docker_image.unhealthy_restart[0].image_id

  ### configure resources.
  shm_size = 64

  ### configure environments.
  env = [
    "AUTOHEAL_CONTAINER_LABEL=${local.unhealthy_restart_label}"
  ]

  ### configure host mounts.
  mounts {
    type   = "bind"
    source = "/var/run/docker.sock"
    target = "/var/run/docker.sock"
  }
}

## create working docker containers.

locals {
  pause_container = format("container:%s", docker_container.pause.id)

  downward_environments = {
    "WALRUS_PROJECT_ID"       = local.project_id
    "WALRUS_ENVIRONMENT_ID"   = local.environment_id
    "WALRUS_RESOURCE_ID"      = local.resource_id
    "WALRUS_PROJECT_NAME"     = local.project_name
    "WALRUS_ENVIRONMENT_NAME" = local.environment_name
    "WALRUS_RESOURCE_NAME"    = local.resource_name
  }

  container_mapping_ephemeral_files_map = {
    for n, fs in local.container_ephemeral_files_map : n => {
      changed = [
        for f in fs : f
        if f.accept_changed
      ]
      no_changed = [
        for f in fs : f
        if !f.accept_changed
      ]
    }
  }
  container_mapping_refer_files_map = {
    for n, fs in local.container_refer_files_map : n => {
      changed = [
        for f in fs : f
        if f.accept_changed
      ]
      no_changed = [
        for f in fs : f
        if !f.accept_changed
      ]
    }
  }
}

locals {
  init_containers_map = {
    for c in local.init_containers : c.name => c
  }
}

data "docker_registry_image" "inits" {
  for_each = toset(keys(try(nonsensitive(local.init_containers_map), local.init_containers_map)))

  name                 = local.init_containers_map[each.key].image
  insecure_skip_verify = true
}

resource "docker_image" "inits" {
  for_each = data.docker_registry_image.inits

  name         = each.value.name
  keep_locally = true
  pull_triggers = [
    each.value.sha256_digest
  ]
}

resource "docker_container" "inits" {
  for_each = toset(keys(try(nonsensitive(local.init_containers_map), local.init_containers_map)))

  name = join("-", [local.fullname, each.key])
  labels {
    label = "walrus.seal.io/container-name"
    value = each.key
  }
  dynamic "labels" {
    for_each = local.labels
    content {
      label = labels.key
      value = labels.value
    }
  }

  ### share from pause container.
  ipc_mode     = local.pause_container
  network_mode = local.pause_container

  ### configure execute.
  must_run    = false
  restart     = "on-failure"
  image       = docker_image.inits[each.key].image_id
  working_dir = try(local.init_containers_map[each.key].execute.working_dir, null)
  entrypoint  = try(local.init_containers_map[each.key].execute.command, null)
  command     = try(local.init_containers_map[each.key].execute.args, null)
  read_only   = try(local.init_containers_map[each.key].execute.readonly_rootfs, false)
  user = try(local.init_containers_map[each.key].execute.as_user != null, false) ? join(":", compact([
    local.init_containers_map[each.key].execute.as_user,
    try(local.init_containers_map[each.key].execute.as_group, null)
  ])) : null
  group_add = try(var.deployment.fs_group != null, false) ? compact([
    try(local.init_containers_map[each.key].execute.as_user == null && local.init_containers_map[each.key].execute.as_group != null, false) ? local.init_containers_map[each.key].execute.as_group : null,
    try(var.deployment.fs_group, null)
  ]) : null
  privileged = try(local.init_containers_map[each.key].execute.privileged, null)

  ### configure resources.
  shm_size    = 64
  cpu_shares  = try(local.init_containers_map[each.key].resources != null && local.init_containers_map[each.key].resources.cpu > 0, false) ? ceil(1024 * local.init_containers_map[each.key].resources.cpu) : null
  memory      = try(local.init_containers_map[each.key].resources != null && local.init_containers_map[each.key].resources.memory > 0, false) ? local.init_containers_map[each.key].resources.memory : null
  memory_swap = try(local.init_containers_map[each.key].resources != null && local.init_containers_map[each.key].resources.memory > 0, false) ? local.init_containers_map[each.key].resources.memory : 0
  gpus        = try(local.init_containers_map[each.key].resources != null && local.init_containers_map[each.key].resources.gpus > 0, false) ? "all" : null # only all is supported at present.

  ### configure environments.
  env = [
    for k, v in merge(
      {
        for e in try(local.container_ephemeral_envs_map[each.key], []) : e.name => e.value
      },
      {
        for e in try(local.container_refer_envs_map[each.key], []) : e.name => e.value_refer.params.name
      },
      local.downward_environments
    ) : format("%s=%s", k, v)
  ]

  ### configure ephemeral files.
  dynamic "mounts" {
    for_each = try(try(nonsensitive(local.container_mapping_ephemeral_files_map[each.key].changed), local.container_mapping_ephemeral_files_map[each.key].changed), [])
    content {
      type      = "bind"
      source    = abspath(local_file.ephemeral_files[mounts.value.name].filename)
      target    = mounts.value.path
      read_only = try(anytrue([floor(tonumber(mounts.value.mode) / 100) % 2 != 1, floor(tonumber(mounts.value.mode) / 10) % 2 != 1, tonumber(mounts.value.mode) % 2 != 1]), true)
    }
  }
  dynamic "upload" {
    for_each = try(try(nonsensitive(local.container_mapping_ephemeral_files_map[each.key].no_changed), local.container_mapping_ephemeral_files_map[each.key].no_changed), [])
    content {
      source     = abspath(local_file.ephemeral_files[upload.value.name].filename)
      file       = upload.value.path
      executable = try(floor(tonumber(upload.value.mode) / 100) % 2 == 1, false)
    }
  }

  ### configure refer files.
  dynamic "mounts" {
    for_each = try(try(nonsensitive(local.container_mapping_refer_files_map[each.key].changed), local.container_mapping_refer_files_map[each.key].changed), [])
    content {
      type      = "bind"
      source    = abspath(mounts.value.content_refer.params.path)
      target    = mounts.value.path
      read_only = try(anytrue([floor(tonumber(mounts.value.mode) / 100) % 2 != 1, floor(tonumber(mounts.value.mode) / 10) % 2 != 1, tonumber(mounts.value.mode) % 2 != 1]), true)
    }
  }
  dynamic "upload" {
    for_each = try(try(nonsensitive(local.container_mapping_refer_files_map[each.key].no_changed), local.container_mapping_refer_files_map[each.key].no_changed), [])
    content {
      source     = abspath(upload.value.content_refer.params.path)
      file       = upload.value.path
      executable = try(floor(tonumber(upload.value.mode) / 100) % 2 == 1, false)
    }
  }

  ### configure ephemeral mounts.
  dynamic "mounts" {
    for_each = try(try(nonsensitive(local.container_ephemeral_mounts_map[each.key]), local.container_ephemeral_mounts_map[each.key]), [])
    content {
      type      = "volume"
      source    = docker_volume.ephemeral_volumes[mounts.value.name].name
      target    = mounts.value.path
      read_only = try(mounts.value.readonly, false)
      # sub_path  = try(mounts.value.subpath, null) # NB(thxCode): block by https://github.com/moby/moby/pull/45687.
    }
  }

  ### configure refer mounts.
  dynamic "mounts" {
    for_each = try(try(nonsensitive(local.container_refer_mounts_map[each.key]), local.container_refer_mounts_map[each.key]), [])
    content {
      type      = "volume"
      source    = mounts.value.volume_refer.params.name
      target    = mounts.value.path
      read_only = try(mounts.value.readonly, false)
      # sub_path  = try(mounts.value.subpath, null) # NB(thxCode): block by https://github.com/moby/moby/pull/45687.
    }
  }

  depends_on = [
    docker_container.pause
  ]
  lifecycle {
    postcondition {
      condition     = try(self.exit_code == null || self.exit_code == 0, true)
      error_message = "Init container must exit with code 0"
    }
    replace_triggered_by = [
      docker_container.pause
    ]
  }
}

locals {
  run_containers_map = {
    for c in local.run_containers : c.name => c
  }
}

data "docker_registry_image" "runs" {
  for_each = toset(keys(try(nonsensitive(local.run_containers_map), local.run_containers_map)))

  name                 = local.run_containers_map[each.key].image
  insecure_skip_verify = true
}

resource "docker_image" "runs" {
  for_each = data.docker_registry_image.runs

  name         = each.value.name
  keep_locally = true
  pull_triggers = [
    each.value.sha256_digest
  ]
}

resource "terraform_data" "run_resources" {
  for_each = toset(keys(try(nonsensitive(local.run_containers_map), local.run_containers_map)))

  input = local.run_containers_map[each.key].resources
}

resource "terraform_data" "run_checks" {
  for_each = toset(keys(try(nonsensitive(local.run_containers_map), local.run_containers_map)))

  input = try(slice([
    for c in try(local.run_containers_map[each.key].checks, []) : c
    if try(lookup(c, c.type, null) != null, false)
  ], 0, 1), [])
}

resource "terraform_data" "run_executes" {
  for_each = toset(keys(try(nonsensitive(local.run_containers_map), local.run_containers_map)))

  input = local.run_containers_map[each.key].execute
}

resource "docker_container" "runs" {
  for_each = toset(keys(try(nonsensitive(local.run_containers_map), local.run_containers_map)))

  name = join("-", [local.fullname, each.key])
  labels {
    label = "walrus.seal.io/container-name"
    value = each.key
  }
  dynamic "labels" {
    for_each = local.labels
    content {
      label = labels.key
      value = labels.value
    }
  }
  dynamic "labels" {
    for_each = local.unhealthy_restart ? [{}] : []
    content {
      label = local.unhealthy_restart_label
      value = "true"
    }
  }

  ### share from pause container.
  ipc_mode     = local.pause_container
  network_mode = local.pause_container

  ### configure execute.
  must_run    = true
  restart     = "always"
  image       = docker_image.runs[each.key].image_id
  working_dir = try(local.run_containers_map[each.key].execute.working_dir, null)
  entrypoint  = try(local.run_containers_map[each.key].execute.command, null)
  command     = try(local.run_containers_map[each.key].execute.args, null)
  read_only   = try(local.run_containers_map[each.key].execute.readonly_rootfs, false)
  user = try(local.run_containers_map[each.key].execute.as_user != null, false) ? join(":", compact([
    local.run_containers_map[each.key].execute.as_user,
    try(local.run_containers_map[each.key].execute.as_group, null)
  ])) : null
  group_add = try(var.deployment.fs_group != null, false) ? compact([
    try(local.run_containers_map[each.key].execute.as_user == null && local.run_containers_map[each.key].execute.as_group != null, false) ? local.run_containers_map[each.key].execute.as_group : null,
    try(var.deployment.fs_group, null)
  ]) : null
  privileged = try(local.run_containers_map[each.key].execute.privileged, null)

  ### configure resources.
  shm_size    = 64
  cpu_shares  = try(local.run_containers_map[each.key].resources != null && local.run_containers_map[each.key].resources.cpu > 0, false) ? ceil(1024 * local.run_containers_map[each.key].resources.cpu) : null
  memory      = try(local.run_containers_map[each.key].resources != null && local.run_containers_map[each.key].resources.memory > 0, false) ? local.run_containers_map[each.key].resources.memory : null
  memory_swap = try(local.run_containers_map[each.key].resources != null && local.run_containers_map[each.key].resources.memory > 0, false) ? local.run_containers_map[each.key].resources.memory : 0
  gpus        = try(local.run_containers_map[each.key].resources != null && local.run_containers_map[each.key].resources.gpus > 0, false) ? "all" : null # only all is supported at present.

  ### configure environments.
  env = [
    for k, v in merge(
      {
        for e in try(local.container_ephemeral_envs_map[each.key], []) : e.name => e.value
      },
      {
        for e in try(local.container_refer_envs_map[each.key], []) : e.name => e.value_refer.params.name
      },
      local.downward_environments
    ) : format("%s=%s", k, v)
  ]

  ### configure ephemeral files.
  dynamic "mounts" {
    for_each = try(try(nonsensitive(local.container_mapping_ephemeral_files_map[each.key].changed), local.container_mapping_ephemeral_files_map[each.key].changed), [])
    content {
      type      = "bind"
      source    = abspath(local_file.ephemeral_files[mounts.value.name].filename)
      target    = mounts.value.path
      read_only = try(anytrue([floor(tonumber(mounts.value.mode) / 100) % 2 != 1, floor(tonumber(mounts.value.mode) / 10) % 2 != 1, tonumber(mounts.value.mode) % 2 != 1]), true)
    }
  }
  dynamic "upload" {
    for_each = try(try(nonsensitive(local.container_mapping_ephemeral_files_map[each.key].no_changed), local.container_mapping_ephemeral_files_map[each.key].no_changed), [])
    content {
      source     = abspath(local_file.ephemeral_files[upload.value.name].filename)
      file       = upload.value.path
      executable = try(floor(tonumber(upload.value.mode) / 100) % 2 == 1, false)
    }
  }

  ### configure refer files.
  dynamic "mounts" {
    for_each = try(try(nonsensitive(local.container_mapping_refer_files_map[each.key].changed), local.container_mapping_refer_files_map[each.key].changed), [])
    content {
      type      = "bind"
      source    = abspath(mounts.value.content_refer.params.path)
      target    = mounts.value.path
      read_only = try(anytrue([floor(tonumber(mounts.value.mode) / 100) % 2 != 1, floor(tonumber(mounts.value.mode) / 10) % 2 != 1, tonumber(mounts.value.mode) % 2 != 1]), true)
    }
  }
  dynamic "upload" {
    for_each = try(try(nonsensitive(local.container_mapping_refer_files_map[each.key].no_changed), local.container_mapping_refer_files_map[each.key].no_changed), [])
    content {
      source     = abspath(upload.value.content_refer.params.path)
      file       = upload.value.path
      executable = try(floor(tonumber(upload.value.mode) / 100) % 2 == 1, false)
    }
  }

  ### configure ephemeral mounts.
  dynamic "mounts" {
    for_each = try(try(nonsensitive(local.container_ephemeral_mounts_map[each.key]), local.container_ephemeral_mounts_map[each.key]), [])
    content {
      type      = "volume"
      source    = docker_volume.ephemeral_volumes[mounts.value.name].name
      target    = mounts.value.path
      read_only = try(mounts.value.readonly, false)
      # sub_path  = try(mounts.value.subpath, null) # NB(thxCode): block by https://github.com/moby/moby/pull/45687.
    }
  }

  ### configure refer mounts.
  dynamic "mounts" {
    for_each = try(try(nonsensitive(local.container_refer_mounts_map[each.key]), local.container_refer_mounts_map[each.key]), [])
    content {
      type      = "volume"
      source    = mounts.value.volume_refer.params.name
      target    = mounts.value.path
      read_only = try(mounts.value.readonly, false)
      # sub_path  = try(mounts.value.subpath, null) # NB(thxCode): block by https://github.com/moby/moby/pull/45687.
    }
  }

  ### configure checks.
  dynamic "healthcheck" {
    for_each = try(try(nonsensitive(terraform_data.run_checks[each.key].input), terraform_data.run_checks[each.key].input), [])
    content {
      start_period = try(format("%ds", healthcheck.value.delay), null)
      interval     = try(format("%ds", healthcheck.value.interval), null)
      timeout      = try(format("%ds", healthcheck.value.timeout), null)
      retries      = try(healthcheck.value.retries, null)
      test = try(healthcheck.value.type == "execute", false) ? flatten([
        "CMD",
        healthcheck.value.execute.command
        ]) : try(healthcheck.value.type == "tcp", false) ? [
        "CMD", "sh", "-c",
        format("if [ `command -v netstat` ]; then netstat -an | grep -w %d > /dev/null || exit 1; else cat /etc/services | grep -w %d/tcp > /dev/null || exit 1 ; fi",
          healthcheck.value.tcp.port,
          healthcheck.value.tcp.port,
        )] : try(healthcheck.value.type == "http", false) ? [
        "CMD", "sh", "-c",
        format("if [ `command -v curl` ]; then curl -fsSL -o /dev/null %s http://localhost:%d%s; else wget -q -O /dev/null %s http://localhost:%d%s; fi",
          try(join(" ", [for k, v in healthcheck.value.http.headers : format("--header '%s: %s'", k, v)]), ""), try(healthcheck.value.http.port, 80), try(healthcheck.value.http.path, "/"),
          try(join(" ", [for k, v in healthcheck.value.http.headers : format("--header '%s: %s'", k, v)]), ""), try(healthcheck.value.http.port, 80), try(healthcheck.value.http.path, "/"),
        )] : try(healthcheck.value.type == "https", false) ? [
        "CMD", "sh", "-c",
        format("if [ `command -v curl` ]; then curl -kfsSL -o /dev/null %s https://localhost:%d%s; else wget --no-check-certificate -q -O /dev/null %s https://localhost:%d%s; fi",
          try(join(" ", [for k, v in healthcheck.value.https.headers : format("--header '%s: %s'", k, v)]), ""), try(healthcheck.value.https.port, 443), try(healthcheck.value.https.path, "/"),
          try(join(" ", [for k, v in healthcheck.value.https.headers : format("--header '%s: %s'", k, v)]), ""), try(healthcheck.value.https.port, 443), try(healthcheck.value.https.path, "/"),
      )] : null
    }
  }

  depends_on = [
    docker_container.pause,
    docker_container.inits
  ]
  lifecycle {
    replace_triggered_by = [
      docker_container.pause,
      terraform_data.run_resources[each.key],
      terraform_data.run_checks[each.key],
      terraform_data.run_executes[each.key]
    ]
  }
}
