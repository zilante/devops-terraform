terraform {
  required_providers {
    yandex = {
      source = "yandex-cloud/yandex"
    }
  }
  required_version = ">= 0.13"
}

provider "yandex" {
  zone = "ru-central1-b"
}

resource "yandex_serverless_container" "how-to-site-flask-container" {
   name               = "how-to-site-flask-container"
   memory             = "128"
   service_account_id = "<service_account_id>"
   image {
       url = "cr.yandex/crpl40j7scnlon7pfvec/how-to-site-flask:latest"
       environment = {
          DB_HOST = "rc1b-1h799uxjj48f6n2g.mdb.yandexcloud.net"
          DB_USER = "user1"
          DB = "db"
          MYSQL_ROOT_PASSWORD = "password"
      }
   }
}

resource "yandex_serverless_container" "how-to-site-flask-posts-container" {
   name               = "how-to-site-flask-posts-containr"
   memory             = "128"
   service_account_id = "<service_account_id>"
   image {
       url = "cr.yandex/crpl40j7scnlon7pfvec/how-to-site-posts-flask:latest"
       environment = {
          DB_HOST = "rc1b-1h799uxjj48f6n2g.mdb.yandexcloud.net"
          DB_USER = "user1"
          DB = "db2"
          MYSQL_ROOT_PASSWORD = "password"
      }
   }
}

resource "yandex_compute_instance" "vm-2" {
  name = "how-to-site-bd-client-vm"
  platform_id = "standard-v3"
  allow_stopping_for_update = true

  resources {
    cores  = "2"
    memory = "4"
  }

  network_interface {
    subnet_id = "${yandex_vpc_subnet.subnet-1.id}"
    nat = true
  }

  metadata = {
    ssh-keys = "<ssh-key-public>"
  }

  connection {
    type = "ssh"
    user = "ubuntu"
    private_key = file("~/.ssh/how-to-site-db-client")
    host = "${self.network_interface[0].nat_ip_address}"
  }

  provisioner "remote-exec" {
    inline = [
<<EOT
sudo apt update && sudo apt install -y mysql-client
EOT
    ]
  }

  boot_disk {
    initialize_params {
      image_id = "fd8ch5n0oe99ktf1tu8r"
    }
  }
}

resource "yandex_mdb_mysql_cluster" "my-mysql" {
  name                = "my-mysql"
  environment         = "PRESTABLE"
  network_id          = yandex_vpc_network.network-1.id
  version             = "8.0"
  security_group_ids  = [ yandex_vpc_security_group.mysql-sg.id ]
  deletion_protection = true

  resources {
    resource_preset_id = "s2.micro"
    disk_type_id       = "network-ssd"
    disk_size          = 10
  }

  host {
    zone      = "ru-central1-b"
    assign_public_ip = true
    subnet_id = yandex_vpc_subnet.subnet-1.id
  }
}

resource "yandex_mdb_mysql_database" "db" {
  cluster_id = yandex_mdb_mysql_cluster.my-mysql.id
  name       = "db"
}

resource "yandex_mdb_mysql_database" "db2" {
  cluster_id = yandex_mdb_mysql_cluster.my-mysql.id
  name       = "db2"
}

resource "yandex_mdb_mysql_user" "user1" {
  cluster_id = yandex_mdb_mysql_cluster.my-mysql.id
  name       = "user1"
  password   = "password"
  permission {
    database_name = yandex_mdb_mysql_database.db.name
    roles         = ["ALL"]
  }
  permission {
    database_name = yandex_mdb_mysql_database.db2.name
    roles         = ["ALL"]
  }
}

resource "yandex_vpc_security_group" "mysql-sg" {
  name       = "mysql-sg"
  network_id = yandex_vpc_network.network-1.id

  ingress {
    description    = "MySQL"
    port           = 3306
    protocol       = "TCP"
    v4_cidr_blocks = [ "0.0.0.0/0" ]
  }
}

resource "yandex_vpc_network" "network-1" {
  name = "network1"
}

resource "yandex_vpc_subnet" "subnet-1" {
  name = "subnet1"
  zone = "ru-central1-b"
  v4_cidr_blocks = ["192.168.10.0/24"]
  network_id = "${yandex_vpc_network.network-1.id}"
}

resource "yandex_container_registry" "my-reg" {
  name = "my-registry"
  folder_id = "<folder_id>"
}

resource "yandex_api_gateway" "test-api-gateway" {
  name        = "how-to-site-api-gateway"
  description = "description"
  spec = <<-EOT
    openapi: "3.0.0"
    info:
      version: 1.0.0
      title: Test API
    paths:
      /post-service/{proxy+}:
        x-yc-apigateway-any-method:
          x-yc-apigateway-integration:
            type: serverless_containers
            container_id: bba6ktepcg93mke8veql
            service_account_id: <service_account_id>
          parameters:
          - explode: false
            in: path
            name: proxy
            required: false
            schema:
              default: '-'
              type: string
            style: simple
      /{proxy+}:
        x-yc-apigateway-any-method:
          x-yc-apigateway-integration:
            type: serverless_containers
            container_id: bba6ovpfsau41k2kvio3
            service_account_id: <service_account_id>
          parameters:
          - explode: false
            in: path
            name: proxy
            required: false
            schema:
              default: '-'
              type: string
            style: simple

  EOT
}

output vm2-ip {
  value = "${yandex_compute_instance.vm-2.network_interface[0].nat_ip_address}"
}
