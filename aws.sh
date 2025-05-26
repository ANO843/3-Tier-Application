#!/bin/bash
echo "Creating VPC..."
VPC_ID=$(aws ec2 create-vpc --cidr-block 20.0.0.0/24 --tag-specifications "ResourceType=vpc,Tags=[{Key=Name,Value=script}]" --query 'Vpc.VpcId' --output text)
echo " VPC created: $VPC_ID"

echo "🌐 Creating Subnets..."
SUBNET_ID1=$(aws ec2 create-subnet \
  --vpc-id "$VPC_ID" \
  --cidr-block 20.0.0.0/26 \
  --availability-zone ap-south-1a \
  --tag-specifications 'ResourceType=subnet,Tags=[{Key=Name,Value=Public1}]' \
  --query 'Subnet.SubnetId' --output text)
  echo "✅ Subnet1 created: $SUBNET_ID1"

SUBNET_ID2=$(aws ec2 create-subnet \
  --vpc-id "$VPC_ID" \
  --cidr-block 20.0.0.64/26 \
  --availability-zone ap-south-1b \
  --tag-specifications 'ResourceType=subnet,Tags=[{Key=Name,Value=Public2}]' \
  --query 'Subnet.SubnetId' --output text)
  echo "✅ Subnet2 created: $SUBNET_ID2"

  SUBNET_ID3=$(aws ec2 create-subnet \
  --vpc-id "$VPC_ID" \
  --cidr-block 20.0.0.128/26 \
  --availability-zone ap-south-1a \
  --tag-specifications 'ResourceType=subnet,Tags=[{Key=Name,Value=Private1}]' \
  --query 'Subnet.SubnetId' --output text)
  echo "✅ Subnet3 created: $SUBNET_ID3"
 

SUBNET_ID4=$(aws ec2 create-subnet \
  --vpc-id "$VPC_ID" \
  --cidr-block 20.0.0.192/26 \
  --availability-zone ap-south-1b \
  --tag-specifications 'ResourceType=subnet,Tags=[{Key=Name,Value=private2}]' \
  --query 'Subnet.SubnetId' --output text)
  echo "✅ Subnet4 created: $SUBNET_ID4"

echo "🌍 Creating and attaching Internet Gateway..."
IGW_ID=$(aws ec2 create-internet-gateway \
  --tag-specifications 'ResourceType=internet-gateway,Tags=[{Key=Name,Value=script_igw}]' \
  --query 'InternetGateway.InternetGatewayId' --output text)
  
  aws ec2 attach-internet-gateway --internet-gateway-id "$IGW_ID" --vpc-id "$VPC_ID"
echo "✅ Internet Gateway: $IGW_ID"

echo "🌐 Creating NAT Gateway..."
  EIP_ALLOC_ID=$(aws ec2 allocate-address --domain vpc --query 'AllocationId' --output text)

  NAT_GW_ID=$(aws ec2 create-nat-gateway \
  --subnet-id "$SUBNET_ID1" \
  --allocation-id "$EIP_ALLOC_ID" \
  --query 'NatGateway.NatGatewayId' --output text)


  aws ec2 wait nat-gateway-available --nat-gateway-ids "$NAT_GW_ID"
  echo "✅ NAT Gateway: $NAT_GW_ID"

echo "📡 Creating and configuring Route Tables..."
  RT_PUB=$(aws ec2 create-route-table --vpc-id "$VPC_ID" --query 'RouteTable.RouteTableId' --output text)
  RT_PRIV=$(aws ec2 create-route-table --vpc-id "$VPC_ID" --query 'RouteTable.RouteTableId' --output text)


  aws ec2 associate-route-table --route-table-id "$RT_PUB" --subnet-id "$SUBNET_ID1"
  aws ec2 associate-route-table --route-table-id "$RT_PUB" --subnet-id "$SUBNET_ID2"

  aws ec2 associate-route-table --route-table-id "$RT_PRIV" --subnet-id "$SUBNET_ID3"
  aws ec2 associate-route-table --route-table-id "$RT_PRIV" --subnet-id "$SUBNET_ID4"
  
   aws ec2 modify-subnet-attribute --subnet-id "$SUBNET_ID1" --map-public-ip-on-launch
   aws ec2 modify-subnet-attribute --subnet-id "$SUBNET_ID2" --map-public-ip-on-launch


  aws ec2 create-route --route-table-id "$RT_PUB" --destination-cidr-block 0.0.0.0/0 --gateway-id "$IGW_ID"
  aws ec2 create-route --route-table-id "$RT_PRIV" --destination-cidr-block 0.0.0.0/0 --nat-gateway-id "$NAT_GW_ID"
echo "✅ Route tables configured"

echo "🔒 Creating Security Groups..."
  SG_PUBLIC=$(aws ec2 create-security-group \
  --group-name PublicSG \
  --description "Allow HTTP/SSH" \
  --vpc-id "$VPC_ID" \
  --query 'GroupId' --output text)

aws ec2 authorize-security-group-ingress --group-id "$SG_PUBLIC" \
  --protocol tcp --port 22 --cidr 0.0.0.0/0
aws ec2 authorize-security-group-ingress --group-id "$SG_PUBLIC" \
  --protocol tcp --port 80 --cidr 0.0.0.0/0


SG_PRIVATE=$(aws ec2 create-security-group \
  --group-name PrivateSG \
  --description "Allow Backend Access" \
  --vpc-id "$VPC_ID" \
  --query 'GroupId' --output text)

  aws ec2 authorize-security-group-ingress --group-id "$SG_PRIVATE" \
  --protocol tcp --port 8000 --source-group "$SG_PUBLIC"
  aws ec2 authorize-security-group-ingress --group-id "$SG_PRIVATE" \
  --protocol tcp --port 22 --source-group "$SG_PUBLIC"

echo "🔒 Creating dedicated RDS security group..."

SG_RDS=$(aws ec2 create-security-group \
  --group-name RDSAccessSG \
  --description "Allow MySQL from backend only" \
  --vpc-id "$VPC_ID" \
  --query 'GroupId' --output text)

echo "✅ RDS security group created: $SG_RDS"

echo "🔐 Allowing backend EC2 SG ($SG_PRIVATE) to access RDS SG ($SG_RDS) on port 3306..."

aws ec2 authorize-security-group-ingress \
  --group-id "$SG_RDS" \
  --protocol -1 \
  --source-group "$SG_PRIVATE"

echo "✅ Ingress rule added for RDS access"

echo "✅ Security groups created"

echo "Creating rds subnet groups"

aws rds create-db-subnet-group \
  --db-subnet-group-name parth \
  --db-subnet-group-description "DB subnet group" \
  --subnet-ids "$SUBNET_ID3" "$SUBNET_ID4" \
  --tags Key=Name,Value=chat_db


echo "🛢️ Creating RDS instance..."

  aws rds create-db-instance \
  --db-instance-identifier scriptmydb \
  --db-instance-class db.t3.micro \
  --engine mysql \
  --master-username admin \
  --master-user-password An20112007# \
  --allocated-storage 20 \
  --vpc-security-group-ids "$SG_RDS" \
  --db-subnet-group-name parth \
  --no-publicly-accessible \
  --db-name parth

echo "⏳ Waiting for RDS to be available..."
  aws rds wait db-instance-available --db-instance-identifier scriptmydb

# Get endpoint
  RDS_END=$(aws rds describe-db-instances \
  --db-instance-identifier scriptmydb \
  --query 'DBInstances[0].Endpoint.Address' \
  --output text)
echo "✅ RDS endpoint: $RDS_END"

    FRONTEND_AMI=ami-04186d24053c4da01
    BACKEND_AMI=ami-081f4d9a35ee4ec75

echo "🚀 Launching backend EC2 instance..."

    aws ec2 run-instances \
  --image-id "$BACKEND_AMI" \
  --count 1 \
  --instance-type t2.micro \
  --key-name "assingment" \
  --security-group-ids "$SG_PRIVATE" \
  --subnet-id "$SUBNET_ID3" \
  --user-data "#!/bin/bash
    apt update -y
    
cat <<EOT > .env
DB_NAME=parth
DB_USER=admin
DB_PASSWORD=An20112007#
DB_HOST="$RDS_END"
DB_PORT=3306
EOT

chown -R chatapp:chatapp /chat_app
cd /chat_app
source venv/bin/activate
cd fundoo
python3 manage.py makemigrations
python3 manage.py migrate" \
 --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=ScriptBackend}]'


 echo "✅ backend EC2 launched and user-data initialized"


BACKEND_INSTANCE_ID=$(aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=ScriptBackend" "Name=instance-state-name,Values=running" \
  --query 'Reservations[0].Instances[0].InstanceId' \
  --output text)


echo "backend_instance_id: $BACKEND_INSTANCE_ID"

aws ec2 wait instance-running --instance-ids "$BACKEND_INSTANCE_ID"


BACKEND_PRIVATE_IP=$(aws ec2 describe-instances \
  --instance-ids "$BACKEND_INSTANCE_ID" \
  --query 'Reservations[0].Instances[0].PrivateIpAddress' \
  --output text)

if [ -z "$BACKEND_PRIVATE_IP" ] || [ "$BACKEND_PRIVATE_IP" == "None" ]; then
  echo "❌ Failed to get backend private IP"
  exit 1
fi

echo "✅ Private IP of backend instance: $BACKEND_PRIVATE_IP"

  aws ec2 run-instances \
  --image-id "$FRONTEND_AMI" \
  --count 1 \
  --instance-type t2.micro \
  --key-name "assingment" \
  --security-group-ids "$SG_PUBLIC" \
  --subnet-id "$SUBNET_ID1" \
  --associate-public-ip-address \
  --user-data "#!/bin/bash
    apt update -y
apt install nginx -y

cat <<EOF > /etc/nginx/sites-available/chatapp.conf
server {
    listen 80;
    server_name _;

    location / {
        proxy_pass http://$BACKEND_PRIVATE_IP:8000;
    }
}
EOF

systemctl enable nginx
systemctl restart nginx
"\
 --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=Scriptfrontend}]'

echo '✅ Nginx configured and started'
