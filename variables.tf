variable "region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "t3.small"
}

variable "ami_id" {
  description = "Ubuntu 22.04 AMI ID (region-specific)"
  type        = string
  default     = "ami-0c7217cdde317cfec" # Ubuntu 22.04 us-east-1
}