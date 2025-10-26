locals {
  private_endpoints_role_assignments = { for ra in flatten([
    for pe_k, pe_v in var.private_endpoints : [
      for ra_k, ra_v in pe_v.role_assignments : {
        private_endpoint_key = pe_k
        role_assignment_key  = ra_k
        role_assignment      = ra_v
      }
    ]
  ]) : "${ra.private_endpoint_key}-${ra.role_assignment_key}" => ra }
}

resource "azurerm_private_endpoint" "this_manage_private_dns_zone_group" {
  for_each = { for k, v in var.private_endpoints : k => v if v.private_dns_zone_group != null }

  name                          = coalesce(each.value.name, "pe-${var.db_server_name}")
  resource_group_name           = coalesce(each.value.resource_group_name, data.azurerm_resource_group.rg.name)
  location                      = coalesce(each.value.location, data.azurerm_resource_group.rg.location)
  subnet_id                     = each.value.subnet_id
  custom_network_interface_name = each.value.custom_network_interface_name
  tags                          = each.value.tags

  private_service_connection {
    name                           = coalesce(each.value.private_service_connection_name, "pse-${var.db_server_name}")
    is_manual_connection           = false
    private_connection_resource_id = azurerm_postgresql_flexible_server.postgres.id
    subresource_names              = ["postgresqlServer"]
  }

  private_dns_zone_group {
    name                 = each.value.private_dns_zone_group.name
    private_dns_zone_ids = each.value.private_dns_zone_group.private_dns_zone_ids
  }

  dynamic "ip_configuration" {
    for_each = each.value.ip_configurations

    content {
      name               = ip_configuration.value.name
      private_ip_address = ip_configuration.value.private_ip_address
      subresource_name   = "postgresqlServer"
      member_name        = "postgresqlServer"
    }
  }
}

resource "azurerm_private_endpoint" "this_unmanaged_private_dns_zone_group" {
  for_each = { for k, v in var.private_endpoints : k => v if v.private_dns_zone_group == null }

  name                          = coalesce(each.value.name, "pe-${var.db_server_name}")
  resource_group_name           = coalesce(each.value.resource_group_name, data.azurerm_resource_group.rg.name)
  location                      = coalesce(each.value.location, data.azurerm_resource_group.rg.location)
  subnet_id                     = each.value.subnet_id
  custom_network_interface_name = each.value.custom_network_interface_name
  tags                          = each.value.tags

  private_service_connection {
    name                           = coalesce(each.value.private_service_connection_name, "pse-${var.db_server_name}")
    is_manual_connection           = false
    private_connection_resource_id = azurerm_postgresql_flexible_server.postgres.id
    subresource_names              = ["postgresqlServer"]
  }

  dynamic "ip_configuration" {
    for_each = each.value.ip_configurations

    content {
      name               = ip_configuration.value.name
      private_ip_address = ip_configuration.value.private_ip_address
      subresource_name   = "postgresqlServer"
      member_name        = "postgresqlServer"
    }
  }

  lifecycle {
    ignore_changes = [private_dns_zone_group]
  }
}

resource "azurerm_role_assignment" "private_endpoint" {
  for_each = local.private_endpoints_role_assignments

  name                                   = each.value.role_assignment.name
  scope                                  = try(azurerm_private_endpoint.this_manage_private_dns_zone_group[each.value.private_endpoint_key].id, azurerm_private_endpoint.this_unmanaged_private_dns_zone_group[each.value.private_endpoint_key].id)
  role_definition_id                     = strcontains(lower(each.value.role_assignment.role_definition_id_or_name), lower(local.role_definition_id_substring)) ? each.value.role_assignment.role_definition_id_or_name : null
  role_definition_name                   = strcontains(lower(each.value.role_assignment.role_definition_id_or_name), lower(local.role_definition_id_substring)) ? null : each.value.role_assignment.role_definition_id_or_name
  principal_id                           = each.value.role_assignment.principal_id
  principal_type                         = each.value.role_assignment.principal_type
  condition                              = each.value.role_assignment.condition
  condition_version                      = each.value.role_assignment.condition_version
  delegated_managed_identity_resource_id = each.value.role_assignment.delegated_managed_identity_resource_id
  description                            = each.value.role_assignment.description
  skip_service_principal_aad_check       = each.value.role_assignment.skip_service_principal_aad_check
}
