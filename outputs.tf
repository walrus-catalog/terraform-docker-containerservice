locals {
  hosts = [
    format("%s.%s.svc.%s", local.resource_name, local.namespace, local.domain_suffix)
  ]

  ports = flatten([
    for c in local.containers : [
      for p in c.ports : try(nonsensitive(p.internal), p.internal)
      if try(p.internal != null, false)
    ]
    if c != null
  ])

  endpoints = length(local.ports) > 0 ? flatten([
    for c in local.hosts : formatlist("%s:%d", c, local.ports)
  ]) : []
}

#
# Orchestration
#

output "context" {
  description = "The input context, a map, which is used for orchestration."
  value       = var.context
}

output "refer" {
  description = "The refer, a map, including hosts, ports and account, which is used for dependencies or collaborations."
  sensitive   = true
  value = {
    schema = "docker:container"
    params = {
      selector  = local.labels
      name      = local.fullname
      hosts     = local.hosts
      ports     = try(nonsensitive(local.ports), local.ports)
      endpoints = try(nonsensitive(local.endpoints), local.endpoints)
    }
  }
}

#
# Reference
#

output "connection" {
  description = "The connection, a string combined host and port, might be a comma separated string or a single string."
  value       = join(",", try(nonsensitive(local.endpoints), local.endpoints))
}

output "address" {
  description = "The address, a string only has host, might be a comma separated string or a single string."
  value       = join(",", local.hosts)
}

output "ports" {
  description = "The port list of the service."
  value       = try(nonsensitive(local.ports), local.ports)
}

#
# Publish
#

locals {
  publish_endpoints = length(local.publish_ports) > 0 ? {
    for xp in [
      for p in local.publish_ports : p
      if p.schema != null
    ] : format("%d:%d/%s", try(nonsensitive(xp.external), xp.external), try(nonsensitive(xp.internal), xp.internal), try(nonsensitive(xp.schema), xp.schema)) =>
    format("%s://localhost:%d", try(nonsensitive(xp.schema), xp.schema), try(nonsensitive(xp.external), xp.external))
  } : {}
}

output "endpoints" {
  description = "The endpoints, a string map, the key is the name, and the value is the URL."
  value       = try(nonsensitive(local.publish_endpoints), local.publish_endpoints)
}
