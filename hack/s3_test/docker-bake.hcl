target "buildkit" {
  context = "../../"
  cache-from = ["type=gha,scope=binaries"]
  secret = [
    "id=ARTIFACTORY_APT_AUTH_CONF",
    "id=ARTIFACTORY_BASE64_GPG"
  ]
}

target "default" {
  contexts = {
    buildkit = "target:buildkit"
  }
  tags = ["moby/buildkit:s3test"]
}
