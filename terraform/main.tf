provider "nomad" {
  address = "http://127.0.0.1:4646"
}

resource "nomad_job" "minio" {
  jobspec = file("${path.cwd}/../nomad/minio.hcl")
  detach = false
}
resource "nomad_job" "hive" {
  jobspec = file("${path.cwd}/../nomad/hive.hcl")
  detach = false
}
resource "nomad_job" "presto" {
  jobspec = file("${path.cwd}/../nomad/presto.hcl")
  detach = false
}
