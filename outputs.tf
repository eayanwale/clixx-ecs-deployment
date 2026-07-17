output "clixx_ecs_url" {
  description = "Public URL for Clixx"
  value       = "https://ecs.${trimsuffix(data.aws_route53_zone.root-domain.name, ".")}"
}

output "bastion_ip" {
  description = "Public IP for Bastion"
  value       = aws_instance.bastion.public_ip
}

output "clixx_ecs_priv_ips" {
  description = "Clixx private IP"
  value       = [data.aws_instances.ecs_nodes.private_ips]
}