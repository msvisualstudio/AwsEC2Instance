#!/bin/bash -ex
vpc_cidr="10.0.0.0/16"
subnet_cidr="10.0.1.0/24"
region="us-east-1"
az="us-east-1a"
#AMI AMAZON LINUX 2
amiID="ami-0b5eea76982371e91"
key_name="OracleAWSWeb"

#Create a new VPC

vpc_id=$(aws ec2 create-vpc --region $region --cidr-block $vpc_cidr | jq .Vpc.VpcId | tr -d '"')
echo "VPC ID: $vpc_id"

#Create a new subnet in that VPC

subnet_id=$(aws ec2 create-subnet --region $region --cidr-block $subnet_cidr --availability-zone $az --vpc-id $vpc_id | jq .Subnet.SubnetId | tr -d '"')
echo "Subnet ID: $subnet_id"

#Setup route table for that subnet
route_table_id=$( aws ec2 create-route-table --region $region --vpc-id $vpc_id | jq .RouteTable.RouteTableId | tr -d '"')

echo "Route table ID: $route_table_id"

aws ec2 associate-route-table --route-table-id $route_table_id --subnet-id $subnet_id

#Create an internet gateway for that route table
ig_id=$(aws ec2 create-internet-gateway --region $region | jq .InternetGateway.InternetGatewayId | tr -d '"')

echo "Internet Gateway ID: $ig_id"

aws ec2 attach-internet-gateway --region $region --internet-gateway-id $ig_id --vpc-id $vpc_id

aws ec2 create-route --region $region --route-table-id $route_table_id --destination-cidr-block "0.0.0.0/0" --gateway-id $ig_id

#Create "Security group that allows internet traffic on port 80 and 22

sg_id=$( aws ec2 create-security-group --region $region --description "Allows http access and ssh" --group-name "public-sg" --vpc-id $vpc_id | jq .GroupId | tr -d '"' )

echo "Security Group ID: $sg_id"

aws ec2 authorize-security-group-ingress --region $region --group-id $sg_id --protocol "tcp"  --port "80" --cidr "0.0.0.0/0"
aws ec2 authorize-security-group-ingress --region $region --group-id $sg_id --protocol "tcp" --port "22" --cidr "0.0.0.0/0"

#Create a new EC2 on that subnet with sg
instance_id=$(aws ec2 run-instances --region $region --image-id $amiID --count 1 --instance-type t2.micro --key-name $key_name --security-group-ids $sg_id --subnet-id $subnet_id | jq .Instances[0].InstanceId | tr -d '"')

echo "Instance ID: $instance_id"

public_ip=$(aws ec2 describe-instances --region $region --instances-id $instance_id | jq ".Reservations[0].Instances[0].PublicAddress" | tr -d '"')

echo "waiting for $instance_id"
aws ec2 wait instance-running --instance-ids $instance_id
publicname="$(aws ec2 describe-instances --instance-ids $instance_id --query "Reservations[0].Instances[0].PublicDnsName" --output text)"

echo "ssh -i OracleAWSKey.pem ec2-user@$publicname"

echo "

SUCCESS!!!

vpc_cidr: $vpc_cidr
subnet_cidr: $subnet_cidr
region: $region
az: $az
vpc_id: $vpc_id
subnet_id: $subnet_id
route_table_id: $route_table_id
ig_id: $ig_id
sg_id: $sg_id
instance_id: $instance_id
public_ip: $public_ip
vpc_cidr: $vpc_cidr
subnet_cidr: $subnet_cidr

The public Ip address is: $public_ip " 

read -r -p "To terminate instance $instance_id  press [ENTER]..."
aws ec2 terminate-instances --instance-ids $instance_id
echo "terminating..."
aws ec2 wait instance-terminated --instance-ids $instance_id
aws ec2 delete-security-group --group-id $sg_id
aws ec2 delete-subnet --subnet-id $subnet_id
aws ec2 delete-vpc --vpc-id $vpc_id
aws ec2 delete-route-table --route-table-id $route_table_id
echo "done"
                                                                               
