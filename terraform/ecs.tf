resource "aws_ecs_cluster" "main" {
  name = "devops-cluster"
}

resource "aws_ecs_task_definition" "app" {
  family                   = "devops-task"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "256"
  memory                   = "512"

  container_definitions = jsonencode([
    {
      name      = "app"
      image     = "docker.io/shadab1995/particle41devopschallenge:latest"
      essential = true

      portMappings = [
        {
          containerPort = 3000
          protocol      = "tcp"
        }
      ]
    }
  ])
}

# ✅ ECS Security Group (ONLY allow from ALB)
resource "aws_security_group" "ecs_sg" {
  name   = "ecs-sg"
  vpc_id = aws_vpc.main.id

  ingress {
    from_port       = 3000
    to_port         = 3000
    protocol        = "tcp"
    security_groups = [aws_security_group.alb_sg.id]   # 🔥 FIXED
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_ecs_service" "app" {
  name            = "devops-service"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.app.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    # 🔥 FIX 1: Use PUBLIC subnets
    subnets = [
      aws_subnet.public.id,
      aws_subnet.public_2.id
    ]

    # 🔥 FIX 2: Attach SG
    security_groups = [aws_security_group.ecs_sg.id]

    # 🔥 FIX 3: Enable public IP
    assign_public_ip = true
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.tg.arn
    container_name   = "app"
    container_port   = 3000
  }

  # 🔥 FIX 4: Ensure ALB ready first
  depends_on = [aws_lb_listener.listener]
}