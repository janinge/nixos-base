job "kata-nginx" {
  datacenters = ["earth"]
  type        = "service"

  group "web" {
    count = 1

    constraint {
      attribute = "${meta.container_runtime}"
      value     = "kata-containerd"
    }

    network {
      mode = "bridge"

      port "http" {
        to = 80
      }
    }

    service {
      name = "kata-nginx"
      port = "http"
      tags = [
        "traefik.enable=true",
        "traefik.http.routers.kata-nginx.entrypoints=tailnet",
        "traefik.http.routers.kata-nginx.rule=Host(`kata-nginx.h00t.works`)",
        "traefik.http.routers.kata-nginx.tls.certresolver=letsencrypt",
      ]

      check {
        type     = "http"
        path     = "/"
        interval = "10s"
        timeout  = "2s"
      }
    }

    task "nginx" {
      driver = "containerd-driver"

      config {
        image = "docker.io/library/nginx:alpine"
      }

      resources {
        cpu    = 100
        memory = 128
      }
    }
  }
}
