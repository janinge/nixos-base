# JuiceFS CSI node plugin (one per kata-capable node).
# Run AFTER the controller is healthy:  nomad job run juicefs-node.nomad
job "juicefs-csi-node" {
  datacenters = ["earth"]
  type        = "system"

  constraint {
    attribute = "${meta.juicefs}"
    value     = "true"
  }

  group "node" {
    task "node" {
      driver = "docker"

      config {
        image      = "juicedata/juicefs-csi-driver:v0.24.7"
        runtime    = "runc" # never under the kata shim
        privileged = true
        args = [
          "--endpoint=unix://csi/csi.sock",
          "--logtostderr",
          "--nodeid=${node.unique.name}",
          "--v=5",
          "--by-process=true",
        ]
      }

      env {
        AWS_REGION = "garage" # match Garage's s3_region
      }

      # META_PASSWORD from sops (see controller job).
      template {
        data        = "{{ file \"/run/secrets/rendered/juicefs-csi.env\" }}"
        destination = "secrets/juicefs.env"
        env         = true
      }

      csi_plugin {
        id        = "juicefs"
        type      = "node"
        mount_dir = "/csi"
      }

      resources {
        cpu    = 200
        memory = 512
      }
    }
  }
}
