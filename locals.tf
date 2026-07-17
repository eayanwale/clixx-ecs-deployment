locals {
  RUNNER       = "clixx-ecs"
  ORGANIZATION = data.aws_ssm_parameter.organization.value
  ROLE_NAME    = data.aws_ssm_parameter.role_name.value
  GIT_REPO     = data.aws_ssm_parameter.git_repo.value
}
