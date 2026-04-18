# Nomad Workload Examples

## Kata-backed OCI workloads

`kata-nginx.nomad` is the minimal example for running a normal OCI image with VM isolation through Kata Containers.

The host side is enabled on `sto-c2-01` with:

```nix
cluster.nomad.client = {
  enable = true;
  runtime = "kata-containerd";
  hostVolumes = sharedVolumes;
};

cluster.nomadKata.enable = true;
```

Jobs request this path by using the containerd task driver and constraining to Kata-capable clients:

```hcl
constraint {
  attribute = "${meta.container_runtime}"
  value     = "kata-containerd"
}

task "app" {
  driver = "containerd-driver"
}
```

Networking still uses Nomad bridge networking. The CNI config is rendered from the node metadata, so allocations on `sto-c2-01` receive IPs from `10.42.24.0/24` on `cni-nomad0`, matching the existing routed service-subnet model.

Storage uses the same Nomad host volume declarations as the Podman path. SeaweedFS-backed volumes should continue to constrain on `${meta.storage_weed} == "ready"` so jobs do not land on a node before the FUSE mount is healthy.

The Podman path remains the default for existing clients. Kata clients use `nomad-driver-containerd` with `containerd_runtime = "io.containerd.kata.v2"`; the VM is an OCI runtime implementation detail rather than a separate VM scheduling model.
