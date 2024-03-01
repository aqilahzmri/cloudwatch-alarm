terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "ap-southeast-1"
}

resource "aws_ses_template" "MyTemplate" {
  name    = "MetricsTemplate"
  subject = "CRITICAL Alarm on {{alarm}}"
  html    = "<h2><span style=\"color: #d13212;\">&#x26A0</span>Your Amazon CloudWatch alarm was triggered</h2><table style=\"height: 245px; width: 70%; border-collapse: collapse;\" border=\"1\" cellspacing=\"70\" cellpadding=\"5\"><tbody><tr style=\"height: 45px;\"><td style=\"width: 22.6262%; background-color: #f2f3f3; height: 45px;\"><span style=\"color: #16191f;\"><strong>Impact</strong></span></td><td style=\"width: 60.5228%; background-color: #ffffff; height: 45px;\"><strong><span style=\"color: #d13212;\">Critical</span></strong></td></tr><tr style=\"height: 45px;\"><td style=\"width: 22.6262%; height: 45px; background-color: #f2f3f3;\"><span style=\"color: #16191f;\"><strong>Alarm Name</strong></span></td><td style=\"width: 60.5228%; height: 45px;\">{{alarm}}</td></tr><tr style=\"height: 45px;\"><td style=\"width: 22.6262%; height: 45px; background-color: #f2f3f3;\"><span style=\"color: #16191f;\"><strong>Account</strong></span></td><td style=\"width: 60.5228%; height: 45px;\"><p>{{account}} {{region}})</p></td></tr><tr style=\"height: 45px;\"><td style=\"width: 22.6262%; height: 45px; background-color: #f2f3f3;\"><span style=\"color: #16191f;\"><strong>Instance-id</strong></span></td><td style=\"width: 60.5228%; height: 45px;\">{{instanceId}}</td></tr><tr style=\"height: 45px;\"><td style=\"width: 22.6262%; background-color: #f2f3f3; height: 45px;\"><span style=\"color: #16191f;\"><strong>Date-Time</strong></span></td><td style=\"width: 60.5228%; height: 45px;\">{{datetime}}</td></tr><tr style=\"height: 45px;\"><td style=\"width: 22.6262%; height: 45px; background-color: #f2f3f3;\"><span style=\"color: #16191f;\"><strong>Reason</strong></span></td><td style=\"width: 60.5228%; height: 45px;\">Current value <strong> {{value}} </strong> is {{comparisonoperator}} <strong> {{threshold}} </strong> </td></tr></tbody></table>"
#   text    = "Hello {{name}},\r\nYour favorite animal is {{favoriteanimal}}."
}

resource "aws_sns_topic" "alarm_email" {
  name = "alarm_email"
}

resource "aws_sns_topic_subscription" "sns-topic" {
  topic_arn = aws_sns_topic.alarm_email.arn
  protocol  = "lambda"
  endpoint  = aws_lambda_function.alarm_email_function.arn
}

resource "aws_cloudwatch_log_group" "lambda_log_group" {
  name              = "/aws/lambda/${aws_lambda_function.alarm_email_function.function_name}"
  retention_in_days = 7
  lifecycle {
    prevent_destroy = false
  }
}

resource "aws_lambda_function" "alarm_email_function" {
  function_name    = "alarm-email-function"
  handler          = "cwalarm-formatted-email-lambda.lambda_handler"
  runtime          = "python3.8"
  description      = "CloudWatch alarms email formatter"
  timeout          = 60
  role             = aws_iam_role.lambda_role.arn
  source_code_hash = filebase64sha256("lambda_send_email.zip")
  filename        = "lambda_send_email.zip"

  environment {
    variables = {
      EMAIL_SOURCE             = "devops@regovtech.com"
      EMAIL_TO_ADDRESSES       = "devops@regovtech.com"
      SES_TEMPLATE_CRITICAL    = "MetricsTemplate"
    }
  }
}

resource "aws_iam_role" "lambda_role" {
name   = "Send_Email_Alarm_Role"
assume_role_policy = <<EOF
{
 "Version": "2012-10-17",
 "Statement": [
   {
     "Action": "sts:AssumeRole",
     "Principal": {
       "Service": "lambda.amazonaws.com"
     },
     "Effect": "Allow",
     "Sid": ""
   }
 ]
}
EOF
}

resource "aws_iam_policy" "iam_policy_for_lambda" {
 
 name         = "aws_iam_policy_for_Send_Email_Alarm"
 path         = "/"
 description  = "AWS IAM Policy for managing aws lambda role"
 policy = <<EOF
{
 "Version": "2012-10-17",
 "Statement": [
    {
     "Action": [
        "ses:SendEmail",
        "ses:SendTemplatedEmail",
        "ses:SendRawEmail"
     ],
     "Resource" : "*",
     "Effect"   : "Allow"
    },
    {
     "Action": [
        "lambda:InvokeFunction"
     ],
     "Resource" : "*",
     "Effect"   : "Allow"
    },
    {
     "Action": [
        "sns:Publish"
     ],
     "Resource" : "*",
     "Effect"   : "Allow"
    },
   {
     "Action": [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents",
        "logs:DescribeLogGroups"
     ],
     "Resource": "arn:aws:logs:*:*:*",
     "Effect": "Allow"
   }
 ]
}
EOF
}
 
resource "aws_iam_role_policy_attachment" "attach_iam_policy_to_iam_role" {
 role        = aws_iam_role.lambda_role.name
 policy_arn  = aws_iam_policy.iam_policy_for_lambda.arn
}

resource "aws_lambda_permission" "allow_cloudwatch" {
  statement_id  = "AllowSNSInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.alarm_email_function.function_name
  principal     = "sns.amazonaws.com"
  source_arn    = aws_sns_topic.alarm_email.arn
}

resource "aws_cloudwatch_metric_alarm" "dexhubdb_cpu_alarm" {
  alarm_name          = "dexhubdb_cpu_alarm"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 1
  metric_name         = "CPUUtilization"
  namespace           = "AWS/RDS"
  period              = 900 # 15 minutes
  statistic           = "Average"
  threshold           = min(max(80, 0), 100)
  alarm_description   = "Alarm when CPU exceeds 80% over last 15 minutes"
  alarm_actions       = [aws_sns_topic.alarm_email.arn]
  dimensions = {
    DBInstanceIdentifier = "dev-dexhubdb"
  }
}

resource "aws_cloudwatch_metric_alarm" "burst_balance_too_low" {
  alarm_name          = "dexhubdb_burst_balance"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 1
  metric_name         = "BurstBalance"
  namespace           = "AWS/RDS"
  period              = 600 # 15 minutes
  statistic           = "Average"
  threshold           = min(max(20, 0), 100)
  alarm_description   = "Average database storage burst balance over last 10 minutes too low, expect a significant performance drop soon"
  alarm_actions       = [aws_sns_topic.alarm_email.arn]
  dimensions = {
    DBInstanceIdentifier = "dev-dexhubdb"
  }
}

resource "aws_cloudwatch_metric_alarm" "cpu_credit_balance_too_low" {
  alarm_name          = "dexhubdb_cpu_credit_balance_too_low"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 1
  metric_name         = "CPUCreditBalance"
  namespace           = "AWS/RDS"
  period              = 600
  statistic           = "Average"
  threshold           = max(20, 0)
  alarm_description   = "Average database CPU credit balance over last 10 minutes too low, expect a significant performance drop soon"
  alarm_actions       = [aws_sns_topic.alarm_email.arn]
  dimensions = {
    DBInstanceIdentifier = "dev-dexhubdb"
  }
}

resource "aws_cloudwatch_metric_alarm" "disk_queue_depth_too_high" {
  alarm_name          = "dexhubdb_queue_depth_too_high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "DiskQueueDepth"
  namespace           = "AWS/RDS"
  period              = 600
  statistic           = "Average"
  threshold           = max(64, 0)
  alarm_description   = "Average database disk queue depth over last 10 minutes too high, performance may suffer"
  alarm_actions       = [aws_sns_topic.alarm_email.arn]
  dimensions = {
    DBInstanceIdentifier = "dev-dexhubdb"
  }
}

resource "aws_cloudwatch_metric_alarm" "freeable_memory_too_low" {
  alarm_name          = "dexhubdb_freeable_memory_too_low"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 1
  metric_name         = "FreeableMemory"
  namespace           = "AWS/RDS"
  period              = 600
  statistic           = "Average"
  threshold           = max(64000000, 0) # 64 Megabyte in Byte
  alarm_description   = "Average database freeable memory over last 10 minutes too low, performance may suffer"
  alarm_actions       = [aws_sns_topic.alarm_email.arn]
  dimensions = {
    DBInstanceIdentifier = "dev-dexhubdb"
  }
}

resource "aws_cloudwatch_metric_alarm" "free_storage_space_too_low" {
  alarm_name          = "dexhubdb_free_storage_space_too_low"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 1
  metric_name         = "FreeStorageSpace"
  namespace           = "AWS/RDS"
  period              = 600
  statistic           = "Average"
  threshold           = max(2000000000, 0) # 2 Gigabyte in Byte
  alarm_description   = "Average database free storage space over last 10 minutes too low"
  alarm_actions       = [aws_sns_topic.alarm_email.arn]
  dimensions = {
    DBInstanceIdentifier = "dev-dexhubdb"
  }
}

resource "aws_cloudwatch_metric_alarm" "swap_usage_too_high" {
  alarm_name          = "dexhubdb_swap_usage_too_high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "SwapUsage"
  namespace           = "AWS/RDS"
  period              = 600
  statistic           = "Average"
  threshold           = max(256000000, 0) # 256 Megabyte in Byte 
  alarm_description   = "Average database swap usage over last 10 minutes too high, performance may suffer"
  alarm_actions       = [aws_sns_topic.alarm_email.arn]
  dimensions = {
    DBInstanceIdentifier = "dev-dexhubdb"
  }
}

resource "aws_cloudwatch_metric_alarm" "devdb_cpu_alarm" {
  alarm_name          = "devdb_cpu_alarm"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 1
  metric_name         = "CPUUtilization"
  namespace           = "AWS/RDS"
  period              = 900 # 15 minutes
  statistic           = "Average"
  threshold           = min(max(80, 0), 100)
  alarm_description   = "Alarm when CPU exceeds 80% over last 15 minutes"
  alarm_actions       = [aws_sns_topic.alarm_email.arn]
  dimensions = {
    DBInstanceIdentifier = "devdb"
  }
}

resource "aws_cloudwatch_metric_alarm" "burst_balance_too_low" {
  alarm_name          = "devdb_burst_balance"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 1
  metric_name         = "BurstBalance"
  namespace           = "AWS/RDS"
  period              = 600 # 15 minutes
  statistic           = "Average"
  threshold           = min(max(20, 0), 100)
  alarm_description   = "Average database storage burst balance over last 10 minutes too low, expect a significant performance drop soon"
  alarm_actions       = [aws_sns_topic.alarm_email.arn]
  dimensions = {
    DBInstanceIdentifier = "devdb"
  }
}

resource "aws_cloudwatch_metric_alarm" "cpu_credit_balance_too_low" {
  alarm_name          = "devdb_cpu_credit_balance_too_low"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 1
  metric_name         = "CPUCreditBalance"
  namespace           = "AWS/RDS"
  period              = 600
  statistic           = "Average"
  threshold           = max(20, 0)
  alarm_description   = "Average database CPU credit balance over last 10 minutes too low, expect a significant performance drop soon"
  alarm_actions       = [aws_sns_topic.alarm_email.arn]
  dimensions = {
    DBInstanceIdentifier = "devdb"
  }
}

resource "aws_cloudwatch_metric_alarm" "disk_queue_depth_too_high" {
  alarm_name          = "devdb_queue_depth_too_high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "DiskQueueDepth"
  namespace           = "AWS/RDS"
  period              = 600
  statistic           = "Average"
  threshold           = max(64, 0)
  alarm_description   = "Average database disk queue depth over last 10 minutes too high, performance may suffer"
  alarm_actions       = [aws_sns_topic.alarm_email.arn]
  dimensions = {
    DBInstanceIdentifier = "devdb"
  }
}

resource "aws_cloudwatch_metric_alarm" "freeable_memory_too_low" {
  alarm_name          = "devdb_freeable_memory_too_low"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 1
  metric_name         = "FreeableMemory"
  namespace           = "AWS/RDS"
  period              = 600
  statistic           = "Average"
  threshold           = max(64000000, 0) # 64 Megabyte in Byte
  alarm_description   = "Average database freeable memory over last 10 minutes too low, performance may suffer"
  alarm_actions       = [aws_sns_topic.alarm_email.arn]
  dimensions = {
    DBInstanceIdentifier = "devdb"
  }
}

resource "aws_cloudwatch_metric_alarm" "free_storage_space_too_low" {
  alarm_name          = "devdb_free_storage_space_too_low"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 1
  metric_name         = "FreeStorageSpace"
  namespace           = "AWS/RDS"
  period              = 600
  statistic           = "Average"
  threshold           = max(2000000000, 0) # 2 Gigabyte in Byte
  alarm_description   = "Average database free storage space over last 10 minutes too low"
  alarm_actions       = [aws_sns_topic.alarm_email.arn]
  dimensions = {
    DBInstanceIdentifier = "devdb"
  }
}

resource "aws_cloudwatch_metric_alarm" "swap_usage_too_high" {
  alarm_name          = "devdb_swap_usage_too_high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "SwapUsage"
  namespace           = "AWS/RDS"
  period              = 600
  statistic           = "Average"
  threshold           = max(256000000, 0) # 256 Megabyte in Byte 
  alarm_description   = "Average database swap usage over last 10 minutes too high, performance may suffer"
  alarm_actions       = [aws_sns_topic.alarm_email.arn]
  dimensions = {
    DBInstanceIdentifier = "devdb"
  }
}

#terraform backend configuration, save into the s3 bucket
terraform {
  backend "s3" {
    bucket         = "alerttfstate-bucket"
    key            = "terraform.tfstate"
    region         = "ap-southeast-1"  # Replace with your desired region
  }
}
