# Nomad Workload Examples

## Kata-backed OCI workloads

`kata-nginx.nomad` is the minimal example for running a normal OCI image with VM isolation through Kata Containers.

There are currently no Kata-capable clients in the cluster. The modules and examples are retained so the runtime can be added again when VM isolation is required.

### Add a Kata client

1. Choose an x86_64 host with hardware virtualization exposed (`/dev/kvm`). In
   `cluster/nodes.nix`, ensure its node entry declares the appropriate KVM module,
   normally `kernelModules = [ "kvm-intel" ];` or `[ "kvm-amd" ]`.
2. Import the Kata module in the host file after `nomad.nix`:

   ```nix
   imports = [
     ../modules/nomad.nix
     ../modules/nomad-kata.nix
   ];
   ```
3. Switch that Nomad client from the default rootless Podman runtime and enable
   Kata:

   ```nix
   cluster.nomad.client = {
     enable = true;
     runtime = "kata-docker";
     hostVolumes = sharedVolumes;
   };

   cluster.nomadKata.enable = true;
   ```
4. If the client will run untrusted workloads, preserve their routed source
   addresses and enable the default-deny policy. Add only the internal services
   those workloads require:

   ```nix
   cluster.nomad.client.snat = false;
   cluster.nomadKata.netPolicy = {
     enable = true;
     hostAllowPorts = [ 53 ];
     allow = [
       # { cidr = "10.42.24.1/32"; protocol = "tcp"; port = 5432; }
     ];
   };
   ```
5. Deploy the host, then verify `docker info`, `kata-runtime check`, and
   `/dev/kvm` before scheduling workloads. Confirm Nomad publishes
   `meta.container_runtime = kata-docker`, submit `kata-nginx.nomad`, and check
   its allocation logs.

The Kata client is rootful: `nomad-kata.nix` switches Nomad from the rootless
Podman driver to Docker, installs Kata/QEMU, registers
`io.containerd.kata.v2`, and permits only `runc` and the Kata runtime. Drain the
node before changing an existing client's runtime because its current
allocations cannot be adopted by the other driver.

The host side requires a Nomad client with the Kata Docker runtime enabled:

```nix
cluster.nomad.client = {
  enable = true;
  runtime = "kata-docker";
  hostVolumes = sharedVolumes;
};

cluster.nomadKata.enable = true;
```

Jobs request this path by using the Docker task driver and constraining to Kata-capable clients:

```hcl
constraint {
  attribute = "${meta.container_runtime}"
  value     = "kata-docker"
}

task "app" {
  driver = "docker"

  config {
    runtime = "io.containerd.kata.v2"
  }
}
```

Networking still uses Nomad bridge networking. The CNI config is rendered from the node metadata, so allocations receive IPs from the node's routed service subnet on `cni-nomad0`, matching the existing routed service-subnet model.

Storage uses the same Nomad host volume declarations as the Podman path. SeaweedFS-backed volumes should continue to constrain on `${meta.storage_weed} == "ready"` so jobs do not land on a node before the FUSE mount is healthy.

The Podman path remains the default for existing clients. Kata clients use Nomad's built-in Docker driver with `runtime = "io.containerd.kata.v2"`; the VM is an OCI runtime implementation detail rather than a separate VM scheduling model.

## JuiceFS CSI volumes

`juicefs-controller.nomad`, `juicefs-node.nomad`, `juicefs-volume.hcl`, and `juicefs-smoke.nomad`
deploy the JuiceFS CSI driver (community edition) for dynamic volume provisioning, with data on
Garage (S3) and metadata on the Patroni PostgreSQL primary.

CSI is **scoped to kata-docker nodes** because the node plugin must run privileged with rshared
mount propagation, which needs their rootful Docker runtime. Once a Kata client exists, enable it per-node:

```nix
# cluster/nodes.nix
my-kata-node = { ...; juicefsCsi = true; };
```

The `modules/juicefs-csi.nix` module then (on that node) sets `allow_privileged`, makes
`/var/lib/nomad` rshared, runs dockerd with `MountFlags=shared`, loads `fuse`, renders
`META_PASSWORD` from sops, and publishes `meta.juicefs = "true"`.

Key points:

- Both plugin tasks run with `--by-process=true` (mandatory off-Kubernetes) and `runtime = "runc"`
  (never under the kata shim), even though the node is a kata client.
- The metadata password is supplied via `META_PASSWORD` (sops → host file → task env), not embedded
  in the volume `metaurl` (avoids juicefs-csi-driver#1016 escaping in process-mount mode).
- Object-store credentials live in the volume `secrets {}` block. `juicefs-volume.hcl` is committed
  with secrets **redacted**; render the live copy from sops on a server node and run
  `nomad volume create` from there.

Bootstrap order (after the one-time `juicefs format` and the Garage bucket / Postgres DB / sops
secret are in place):

```sh
nomad job run juicefs-controller.nomad
nomad job run juicefs-node.nomad
nomad plugin status juicefs          # Controllers Healthy >=1, Nodes Healthy = N
nomad volume create juicefs-volume.hcl   # the sops-rendered copy
nomad job run juicefs-smoke.nomad
```

Consumer jobs request the volume and constrain to CSI-capable nodes:

```hcl
constraint { attribute = "${meta.juicefs}"  value = "true" }

group "app" {
  volume "jfs" {
    type            = "csi"
    source          = "juicefs-default"
    access_mode     = "multi-node-multi-writer"
    attachment_mode = "file-system"
  }
  task "app" {
    volume_mount { volume = "jfs"  destination = "/data" }
  }
}
```

Kata consumers (`runtime = "io.containerd.kata.v2"`) of a JuiceFS volume are experimental — the host
FUSE mount must be re-exported into the microVM via virtiofs (nested). Validate before relying on it;
prefer runc/podman consumers, or constrain Kata jobs off JuiceFS if it proves unstable.
