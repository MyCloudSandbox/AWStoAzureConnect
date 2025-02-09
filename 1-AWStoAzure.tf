# --------------- AWS Resources ---------------
resource "aws_vpc" "main" {
  cidr_block = "10.48.0.0/16"

  tags = {
    Name = "main"
  }
}

resource "aws_subnet" "subnet_1" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.48.1.0/24"
  availability_zone = "eu-west-2a"
  tags = {
    Name = "subnet-1"
  }
}

resource "aws_subnet" "subnet_2" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.48.2.0/24"
  availability_zone = "eu-west-2b"
  tags = {
    Name = "subnet-2"
  }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "main-igw"
  }
}

resource "aws_route_table" "route_table" { //This creates the AWS Route Table required for the VPC
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
}

resource "aws_route_table_association" "route_table_association" { //This associates the route table with the subnet
  subnet_id      = aws_subnet.subnet_1.id
  route_table_id = aws_route_table.route_table.id
}

resource "aws_customer_gateway" "aws_cgw_1" { //This creates the AWS Customer Gateway to connect to Azure. We need this to connect to the public IP of the Azure VPN Gateway.
  bgp_asn    = 65000
  ip_address = azurerm_public_ip.azure_public_ip_1.ip_address
  type       = "ipsec.1"
  tags = {
    Name = "aws-cgw-1"
  }
}

resource "aws_customer_gateway" "aws_cgw_2" { // We need this to connect to the second public IP of the Azure VPN Gateway.
  bgp_asn    = 65000
  ip_address = azurerm_public_ip.azure_public_ip_2.ip_address
  type       = "ipsec.1"
  tags = {
    Name = "aws-cgw-2"
  }
}

resource "aws_vpn_gateway" "aws_vpg" {
  vpc_id = aws_vpc.main.id
  tags = {
    Name = "main"
  }
}

resource "aws_vpn_connection" "aws_vpn_connection_1" { //This establishes the AWS VPN Connection to connect to Azure
  vpn_gateway_id      = aws_vpn_gateway.aws_vpg.id
  customer_gateway_id = aws_customer_gateway.aws_cgw_1.id
  type                = "ipsec.1"
  static_routes_only  = true
  tags = {
    Name = "aws-vpn-1"
  }
}

resource "aws_vpn_connection" "aws_vpn_connection_2" { //This establishes the second AWS VPN Connection to connect to Azure
  vpn_gateway_id      = aws_vpn_gateway.aws_vpg.id
  customer_gateway_id = aws_customer_gateway.aws_cgw_2.id
  type                = "ipsec.1"
  static_routes_only  = true
  tags = {
    Name = "aws-vpn-2"
  } 
}

resource "aws_vpn_connection_route" "aws_route_1" {
  vpn_connection_id = aws_vpn_connection.aws_vpn_connection_1.id
  destination_cidr_block = "10.212.0.0/16"  # Azure VNet CIDR
}

resource "aws_vpn_connection_route" "aws_route_2" {
  vpn_connection_id = aws_vpn_connection.aws_vpn_connection_2.id
  destination_cidr_block = "10.212.0.0/16"  # Azure VNet CIDR
}

resource "aws_route" "route_to_azure" { //The route that sends traffic to Azure
  route_table_id         = aws_route_table.route_table.id
  destination_cidr_block = "10.212.0.0/16"
  gateway_id             = aws_vpn_gateway.aws_vpg.id
  
}

# --------------- Azure Resources ---------------
resource "azurerm_resource_group" "rg" {
  name     = "my-resource-group808"
  location = "East US"
}

resource "azurerm_virtual_network" "azure_vnet" {
  name                = "azure-vnet"
  location            = "East US"
  resource_group_name = azurerm_resource_group.rg.name
  address_space       = ["10.212.0.0/16"]
}

resource "azurerm_subnet" "subnet_1" {
  name                 = "Subnet1"
  resource_group_name  = azurerm_virtual_network.azure_vnet.resource_group_name
  virtual_network_name = azurerm_virtual_network.azure_vnet.name
  address_prefixes     = ["10.212.1.0/24"]
}

resource "azurerm_subnet" "gateway_subnet" { //This creates the Azure Gateway Subnet to connect to AWS. This is needed for the VPN Gateway.
  name                 = "GatewaySubnet"
  resource_group_name  = azurerm_virtual_network.azure_vnet.resource_group_name
  virtual_network_name = azurerm_virtual_network.azure_vnet.name
  address_prefixes     = ["10.212.2.0/24"]
}

resource "azurerm_public_ip" "azure_public_ip_1" {
  name                = "azure-public-ip-1"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  allocation_method   = "Static"
  sku                 = "Standard"
}

resource "azurerm_public_ip" "azure_public_ip_2" {
  name                = "azure-public-ip-2"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  allocation_method   = "Static"
  sku                 = "Standard"
}

resource "azurerm_virtual_network_gateway" "azure_vpn_gateway" { //This creates the Azure VPN Gateway to connect to AWS. It has two public IPs for redundancy.
  name                            = "azure-vpn-gateway"
  location                        = azurerm_resource_group.rg.location
  resource_group_name             = azurerm_resource_group.rg.name
  type                            = "Vpn"
  vpn_type                        = "RouteBased"
  active_active                   = true
  enable_bgp                      = false
  sku                             = "VpnGw1"
  ip_configuration { //This creates the Azure VPN Gateway to connect to AWS
    name                          = azurerm_public_ip.azure_public_ip_1.name
    public_ip_address_id          = azurerm_public_ip.azure_public_ip_1.id
    private_ip_address_allocation = "Dynamic"
    subnet_id                     = azurerm_subnet.gateway_subnet.id
  }
  ip_configuration {
    name                          = azurerm_public_ip.azure_public_ip_2.name
    public_ip_address_id          = azurerm_public_ip.azure_public_ip_2.id
    private_ip_address_allocation = "Dynamic"
    subnet_id                     = azurerm_subnet.gateway_subnet.id
  }
}

resource "azurerm_local_network_gateway" "local_network_gateway_tunnel1" { //This creates the Azure Local Network Gateway to connect to AWS which is required for the VPN Gateway Connection.
  name                = "aws_vpn_gateway_1_tunnel1"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  gateway_address     = aws_vpn_connection.aws_vpn_connection_1.tunnel1_address // Use the VPN connection's tunnel1_address
  address_space       = [
    aws_vpc.main.cidr_block  
  ]
}

resource "azurerm_virtual_network_gateway_connection" "virtual_connection_tunnel1" { //This creates the Azure VPN Gateway Connection to connect to AWS
  name                            = "virtual_connection_1_tunnel1"
  location                        = azurerm_resource_group.rg.location
  resource_group_name             = azurerm_resource_group.rg.name
  virtual_network_gateway_id      = azurerm_virtual_network_gateway.azure_vpn_gateway.id
  type                            = "IPsec"
  shared_key                      = aws_vpn_connection.aws_vpn_connection_1.tunnel1_preshared_key  
  local_network_gateway_id        = azurerm_local_network_gateway.local_network_gateway_tunnel1.id

  depends_on = [
    azurerm_virtual_network_gateway.azure_vpn_gateway
  ]
}

resource "azurerm_local_network_gateway" "local_network_gateway_tunnel2" {
  name                = "aws_vpn_gateway_1_tunnel2"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  gateway_address     = aws_vpn_connection.aws_vpn_connection_1.tunnel2_address  // Use the VPN connection's tunnel2_address
  address_space       = [
    aws_vpc.main.cidr_block 
  ]
}

resource "azurerm_virtual_network_gateway_connection" "virtual_connection_tunnel2" {
  name                            = "virtual_connection_1_tunnel2"
  location                        = azurerm_resource_group.rg.location
  resource_group_name             = azurerm_resource_group.rg.name
  virtual_network_gateway_id      = azurerm_virtual_network_gateway.azure_vpn_gateway.id
  type                            = "IPsec"
  shared_key                      = aws_vpn_connection.aws_vpn_connection_1.tunnel2_preshared_key  
  local_network_gateway_id        = azurerm_local_network_gateway.local_network_gateway_tunnel2.id

  depends_on = [
    azurerm_virtual_network_gateway.azure_vpn_gateway
  ]
}

resource "azurerm_local_network_gateway" "local_network_gateway_2_tunnel1" {
  name                = "aws_vpn_gateway_2_tunnel1"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  gateway_address     = aws_vpn_connection.aws_vpn_connection_2.tunnel1_address  // Use the VPN connection's tunnel1_address
  address_space       = [
    aws_vpc.main.cidr_block  
  ]
}

resource "azurerm_virtual_network_gateway_connection" "virtual_connection_2_tunnel1" {
  name                            = "virtual_connection_2_tunnel1"
  location                        = azurerm_resource_group.rg.location
  resource_group_name             = azurerm_resource_group.rg.name
  virtual_network_gateway_id      = azurerm_virtual_network_gateway.azure_vpn_gateway.id
  type                            = "IPsec"
  shared_key                      = aws_vpn_connection.aws_vpn_connection_2.tunnel1_preshared_key  
  local_network_gateway_id        = azurerm_local_network_gateway.local_network_gateway_2_tunnel1.id

  depends_on = [
    azurerm_virtual_network_gateway.azure_vpn_gateway
  ]
}

resource "azurerm_local_network_gateway" "local_network_gateway_2_tunnel2" {
  name                = "aws_vpn_gateway_2_tunnel2"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  gateway_address     = aws_vpn_connection.aws_vpn_connection_2.tunnel2_address  // Use the VPN connection's tunnel2_address
  address_space       = [
    aws_vpc.main.cidr_block 
  ]
}

resource "azurerm_virtual_network_gateway_connection" "virtual_connection_2_tunnel2" {
  name                            = "virtual_connection_2_tunnel2"
  location                        = azurerm_resource_group.rg.location
  resource_group_name             = azurerm_resource_group.rg.name
  virtual_network_gateway_id      = azurerm_virtual_network_gateway.azure_vpn_gateway.id
  type                            = "IPsec"
  shared_key                      = aws_vpn_connection.aws_vpn_connection_2.tunnel2_preshared_key  
  local_network_gateway_id        = azurerm_local_network_gateway.local_network_gateway_2_tunnel2.id

  depends_on = [
    azurerm_virtual_network_gateway.azure_vpn_gateway
  ]
}

