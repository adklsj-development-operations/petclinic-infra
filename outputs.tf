output "public_ip" {
  description = "Public IP of the petclinic EC2 instance"
  value       = aws_instance.petclinic.public_ip
}

output "app_url" {
  description = "URL to reach the app via NodePort"
  value       = "http://${aws_instance.petclinic.public_ip}:30080"
}

output "private_key_pem" {
  description = "Private key for SSH access — add this as EC2_SSH_PRIVATE_KEY in GitHub secrets"
  value       = tls_private_key.petclinic.private_key_pem
  sensitive   = true
}