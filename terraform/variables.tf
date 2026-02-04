variable "aws_region" {
  description = "A região da AWS onde os recursos serão criados"
  default     = "us-east-1"
}

variable "project_name" {
  description = "Prefixo para nomear os recursos do projeto"
  default     = "oncovision-mvp"
}