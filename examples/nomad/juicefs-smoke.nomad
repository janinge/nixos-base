# Smoke test for a JuiceFS CSI volume (runc consumer — fully supported).
# Run after `nomad volume create juicefs-volume.hcl`:
#   nomad job run juicefs-smoke.nomad
#   nomad alloc logs <alloc>   # should show a growing smoke.log
#
# For a Kata consumer test, change runtime to "io.containerd.kata.v2". This is
# EXPERIMENTAL: a host FUSE mount re-exported into a microVM via virtiofs is
# nested and may fail — validate before relying on it.
job "juicefs-smoke" {
  datacenters = ["earth"]
  type        = "batch"

  constraint {
    attribute = "${meta.juicefs}"
    value     = "true"
  }

  group "smoke" {
    volume "jfs" {
      type            = "csi"
      source          = "juicefs-default"
      access_mode     = "multi-node-multi-writer"
      attachment_mode = "file-system"
    }

    task "writer" {
      driver = "docker"

      config {
        image   = "docker.io/library/alpine:3.20"
        runtime = "runc"
        command = "sh"
        args    = ["-c", "echo \"$(date) $(hostname)\" >> /data/smoke.log; cat /data/smoke.log"]
      }

      volume_mount {
        volume      = "jfs"
        destination = "/data"
      }

      resources {
        cpu    = 100
        memory = 64
      }
    }
  }
}
