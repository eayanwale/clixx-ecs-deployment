resource "aws_instance" "bastion" {
  ami                         = "ami-0123456789abcdef0"
  instance_type               = "t3.micro"
  subnet_id                   = aws_subnet.public-subnet-a.id
  vpc_security_group_ids      = [aws_security_group.bastion-sg.id]
  associate_public_ip_address = true
  key_name                    = var.key_name

  tags = {
    Name = "tf-${local.RUNNER}-${local.ORGANIZATION}-bastion-server"
  }
}

resource "aws_lb_target_group" "ecs-tg" {
  name                 = "tf-${local.RUNNER}-container-TG"
  port                 = 80
  protocol             = "HTTP"
  target_type          = "instance"
  vpc_id               = aws_vpc.main.id
  deregistration_delay = 30

  health_check {
    enabled  = true
    path     = "/"
    port     = "traffic-port"
    protocol = "HTTP"
    matcher  = "200,301,302"
  }
}

resource "aws_lb" "ecs-lb" {
  name               = "tf-${local.RUNNER}-${local.ORGANIZATION}-ecs-lb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb-sg.id]
  subnets            = [aws_subnet.public-subnet-a.id, aws_subnet.public-subnet-b.id]

  tags = {
    Name = "tf-${local.RUNNER}-${local.ORGANIZATION}-lb"
  }
}

resource "aws_lb_listener" "ecs-lsnr" {
  load_balancer_arn = aws_lb.ecs-lb.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type = "redirect"

    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }

  tags = {
    Name = "tf-${local.RUNNER}-${local.ORGANIZATION}-lb-listener"
  }
}

resource "aws_lb_listener" "ecs-lsnr-https" {
  load_balancer_arn = aws_lb.ecs-lb.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = "arn:aws:acm:us-east-1:222222222222:certificate/00000000-0000-0000-0000-000000000000"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.ecs-tg.arn
  }
}

resource "aws_autoscaling_group" "ecs-asg" {
  depends_on = [aws_db_instance.clixx-ecs-db]

  name                      = "tf-${local.RUNNER}-${local.ORGANIZATION}-ecs-asg"
  vpc_zone_identifier       = [aws_subnet.private-subnet-a.id, aws_subnet.private-subnet-b.id]
  min_size                  = 1
  max_size                  = 3
  desired_capacity          = 2
  force_delete              = true
  protect_from_scale_in     = false
  health_check_grace_period = 120

  launch_template {
    id      = aws_launch_template.clixx-ecs-lt.id
    version = "$Latest"
  }

  tag {
    key                 = "AmazonECSManaged"
    value               = true
    propagate_at_launch = true
  }
}

resource "aws_launch_template" "clixx-ecs-lt" {
  name_prefix   = "tf-${local.RUNNER}-${local.ORGANIZATION}-ecs-lt"
  image_id      = data.aws_ami.ecs-stack-ami.id
  instance_type = var.ecs_instance_type
  key_name      = var.key_name

  network_interfaces {
    associate_public_ip_address = false
    security_groups             = [aws_security_group.clixx-sg.id]
  }

  iam_instance_profile {
    name = aws_iam_instance_profile.ecs_instance_profile.name
  }

  user_data = base64encode(<<-EOF
    #!/bin/bash
    echo ECS_CLUSTER=${aws_ecs_cluster.clixx-cluster.name} >> /etc/ecs/ecs.config
  EOF
  )

  tag_specifications {
    resource_type = "instance"
    tags          = { Name = "ECS Instance - CLIXX-Cluster" }
  }
}