{
  external-juicefs = {
    fsName = "external-juicefs";
    mountPoint = "/mnt/juicefs/external";
    cacheDir = "/var/cache/juicefs/external";
    cacheSizeMiB = 10240;
    postgresPasswordSecret = "juicefs_external_postgres_password";
    s3EnvSecret = "juicefs_external_s3.env";

    metadata = {
      host = "primary.postgres-cluster.service.consul";
      port = 5432;
      database = "juicefs_external";
      username = "juicefs_external";
      sslmode = "disable";
    };

    nomad.hostVolumes = {
      external-juicefs-p2p = {
        subPath = "p2p";
      };
      external-juicefs-music = {
        subPath = "music";
      };
      external-juicefs-authentik = {
        subPath = "authentik";
      };
    };
  };
}
