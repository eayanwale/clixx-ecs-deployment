resource "aws_cloudwatch_metric_alarm" "cpu_utilization" {
  alarm_name          = "esg-high-cpu-alarm"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = "300"
  statistic           = "Average"
  threshold           = "80"
  alarm_description   = "This metric monitors the average CPU utilization across all instances in the ASG."

  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.ecs-asg.name
  }

  alarm_actions = [aws_sns_topic.warn.arn]
  ok_actions    = [aws_sns_topic.warn.arn]
}

resource "aws_cloudwatch_metric_alarm" "mem_usage" {
  alarm_name          = "esg-high-mem-alarm"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = "2"

  metric_name       = "mem_used_percent"
  namespace         = "CWAgent"
  period            = "300"
  statistic         = "Average"
  threshold         = "85"
  alarm_description = "This metric monitors the average memory utilization across all instances in the ASG."

  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.ecs-asg.name
  }

  alarm_actions = [aws_sns_topic.warn.arn]
  ok_actions    = [aws_sns_topic.warn.arn]
}


resource "aws_cloudwatch_metric_alarm" "disk_usage" {
  alarm_name          = "esg-high-disk-alarm"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = "2"
  threshold           = "85"
  alarm_description   = "Monitors aggregate root disk utilization across all instances in the ASG."

  metric_query {
    id          = "m1"
    return_data = true

    metric {
      metric_name = "disk_used_percent"
      namespace   = "CWAgent"
      period      = "300"
      stat        = "Average"

      dimensions = {
        AutoScalingGroupName = aws_autoscaling_group.ecs-asg.name
        path                 = "/"
      }
    }
  }

  alarm_actions = [aws_sns_topic.warn.arn]
  ok_actions    = [aws_sns_topic.warn.arn]
}

resource "aws_cloudwatch_dashboard" "main" {
  dashboard_name = "clixx-esg-dashboard"

  dashboard_body = jsonencode({
    widgets = [
      {
        type   = "metric"
        x      = 0
        y      = 0
        width  = 12
        height = 6

        properties = {
          metrics = [
            [
              "AWS/EC2",
              "CPUUtilization",
              "AutoScalingGroupName",
              aws_autoscaling_group.ecs-asg.name
            ]
          ]
          period = 300
          stat   = "Average"
          region = "us-east-1"
          title  = "EC2 Instance CPU"
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 10
        width  = 6
        height = 4

        properties = {
          view = "singleValue"
          metrics = [
            [
              "CWAgent",
              "mem_used_percent",
              "AutoScalingGroupName",
              aws_autoscaling_group.ecs-asg.name
            ],
            [
              "CWAgent",
              "disk_used_percent",
              "AutoScalingGroupName",
              aws_autoscaling_group.ecs-asg.name,
              "path",
              "/",
              "fstype",
              "xfs"
            ]
          ]
          period = 300
          stat   = "Average"
          region = "us-east-1"
          title  = "Memory & Disk Usage (%)"
        }
      }
    ]
  })
}