resource "aws_security_group" "web_sg" {
  name_prefix = "web-"

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}


resource "aws_launch_template" "web_lt" {
  name_prefix   = "web-lt"
  image_id      = "ami-0c02fb55956c7d316" # Ubuntu in us-east-1
  instance_type = var.ec2_instance_type
  key_name      = var.key_name
  user_data     = base64encode(file("userdata.sh"))

  vpc_security_group_ids = [aws_security_group.web_sg.id]

  iam_instance_profile {
    name = aws_iam_instance_profile.ec2_profile.name
  }
}


resource "aws_iam_role" "ec2_role" {
  name = "ec2_ssm_role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Action = "sts:AssumeRole",
      Effect = "Allow",
      Principal = {
        Service = "ec2.amazonaws.com"
      }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "ec2_profile" {
  name = "ec2_ssm_profile"
  role = aws_iam_role.ec2_role.name
}


resource "aws_autoscaling_group" "web_asg" {
  desired_capacity     = 2
  max_size             = 3
  min_size             = 1
  launch_template {
    id      = aws_launch_template.web_lt.id
    version = "$Latest"
  }

  vpc_zone_identifier = ["subnet-xxx", "subnet-yyy"]  # Replace with real subnet IDs
  target_group_arns   = [aws_lb_target_group.web_tg.arn]
}

resource "aws_lb" "web_alb" {
  name               = "web-alb"
  internal           = false
  load_balancer_type = "application"
  subnets            = ["subnet-xxx", "subnet-yyy"]
  security_groups    = [aws_security_group.web_sg.id]
}

resource "aws_lb_target_group" "web_tg" {
  name     = "web-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = "vpc-xxx"
}

resource "aws_lb_listener" "web_listener" {
  load_balancer_arn = aws_lb.web_alb.arn
  port              = 80
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.web_tg.arn
  }
}


resource "aws_kms_key" "rds_key" {
  description = "KMS key for RDS password"
  enable_key_rotation = true
}

resource "aws_secretsmanager_secret" "rds_secret" {
  name        = "rds-secret"
  kms_key_id  = aws_kms_key.rds_key.arn
  recovery_window_in_days = 0
  rotation_rules {
    automatically_after_days = 7
  }
}

resource "aws_secretsmanager_secret_version" "rds_secret_value" {
  secret_id     = aws_secretsmanager_secret.rds_secret.id
  secret_string = jsonencode({
    username = var.db_username
    password = var.db_password
  })
}

resource "aws_db_instance" "db" {
  allocated_storage    = 20
  engine               = "mysql"
  instance_class       = "db.t3.micro"
  db_name              = "mydb"
  username             = var.db_username
  password             = var.db_password
  skip_final_snapshot  = true
  publicly_accessible  = true
}


resource "aws_cloudfront_distribution" "cdn" {
  origin {
    domain_name = aws_lb.web_alb.dns_name
    origin_id   = "web-origin"
  }

  enabled             = true
  default_root_object = "/"
  default_cache_behavior {
    target_origin_id = "web-origin"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods = ["GET", "HEAD"]
    cached_methods  = ["GET", "HEAD"]
    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }
}
