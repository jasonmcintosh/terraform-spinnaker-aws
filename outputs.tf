output "NextSteps" {
  value = "ssh ubuntu@${aws_instance.halyard_and_spinnaker_server.public_ip}"
}
