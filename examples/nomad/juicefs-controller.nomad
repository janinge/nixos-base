# JuiceFS CSI controller plugin (dynamic provisioning).
# Run AFTER the NixOS juicefs-csi module is deployed on the kata nodes, and
# BEFORE creating volumes:  nomad job run juicefs-controller.nomad
job "juicefs-csi-controller" {
  datacenters = ["earth"]
  type        = "service"

  # Only schedule where the CSI module published the tag.
  constraint {
    attribute = "${meta.juicefs}"
    value     = "true"
  }

  group "controller" {
    count = 1

    task "controller" {
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
          "--by-process=true", # mandatory on Nomad (no k8s mount pods)
        ]
      }

      # META_PASSWORD for the postgres metadata engine, rendered from sops on the
      # host (kept out of the volume metaurl to avoid juicefs-csi-driver#1016).
      # Requires client.template.disable_file_sandbox = true (already set).
      template {
        data        = "{{ file \"/run/secrets/rendered/juicefs-csi.env\" }}"
        destination = "secrets/juicefs.env"
        env         = true
      }

      csi_plugin {
        id        = "juicefs"
        type      = "controller"
        mount_dir = "/csi"
      }

      resources {
        cpu    = 200
        memory = 256
      }
    }
  }
}
