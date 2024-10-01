variable "ssh_key_file" {
  default = "~/.ssh/key" # CHANGEME
}

variable "instance_name" {
  type = map(object({
    name  = string
  }))
}
