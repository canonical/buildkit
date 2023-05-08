target "buildkit" {
  context = "../../"
  cache-from = ["type=gha,scope=binaries"]
}

target "default" {
  contexts = {
    buildkit = "target:buildkit"
  }
  tags = ["moby/buildkit:azblobtest"]
  secret = ["id=ARTIFACTORY_APT_AUTH_CONF,id=ARTIFACTORY_BASE64_GPG"]
}
