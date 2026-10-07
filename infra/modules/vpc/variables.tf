variable "name" {
  description = "Prefix used in resource names"
  type        = string
}

variable "cidr_block" {
  description = "CIDR range for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "azs" {
  description = "Availability zones to use"
  type        = list(string)
}

variable "enable_nat_gateway" {
  description = "Create a NAT gateway so private subnets can reach the internet (bills hourly)"
  type        = bool
  default     = false
}