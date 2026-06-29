# Dynamic JuiceFS volume.  Create with:  nomad volume create juicefs-volume.hcl
#
# SECRETS ARE REDACTED HERE. Do NOT commit real credentials. The live copy is
# rendered from sops on a server node (e.g. edge-gw / ams-c1-01 / hh4-nomad) and
# `nomad volume create` is run from there. The password is intentionally omitted
# from `metaurl` — the CSI plugin supplies it via META_PASSWORD (see the plugin
# jobs), avoiding the postgres metaurl escaping bug juicefs-csi-driver#1016.

id        = "juicefs-default"
name      = "juicefs-default"
type      = "csi"
plugin_id = "juicefs"

capacity_min = "10G"
capacity_max = "100G"

capability {
  access_mode     = "multi-node-multi-writer"
  attachment_mode = "file-system"
}

secrets {
  name       = "juicefs-default"
  metaurl    = "postgres://juicefs@primary.postgres-cluster.service.consul:5432/juicefs?sslmode=disable"
  storage    = "s3"
  bucket     = "http://garage-s3.service.consul:3900/juicefs"
  access-key = "REDACTED"
  secret-key = "REDACTED"
}
