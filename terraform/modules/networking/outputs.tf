output "vpc_id" {
  value = aws_vpc.main.id
}

output "public_subnets" {
  value = [aws_subnet.public_1.id, aws_subnet.public_2.id, aws_subnet.public_3.id]
  depends_on = [
    aws_route_table_association.public_1,
    aws_route_table_association.public_2,
    aws_route_table_association.public_3
  ]
}

output "private_subnets" {
  value = [aws_subnet.private_1.id, aws_subnet.private_2.id, aws_subnet.private_3.id]
  depends_on = [
    aws_nat_gateway.main,
    aws_route_table_association.private_1,
    aws_route_table_association.private_2,
    aws_route_table_association.private_3
  ]
}