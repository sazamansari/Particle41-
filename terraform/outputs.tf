output "alb_url" {
  value = aws_lb.app_lb.dns_name
}