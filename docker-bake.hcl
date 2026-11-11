variable "REGISTRY" {
  default = "ghcr.io/autonomy-logic"
}

variable "SOURCE_DATE_EPOCH" {
  default = "0"
}

variable "ROOT_PACKAGE" {
  default = "autonomy-base"
}

variable "ROOT_TAG" {
  default = "dev"
}

variable "ROOT_DIGEST" {
  default = ""
}

variable "PYTHON_PACKAGE" {
  default = "autonomy-python-base"
}

variable "PYTHON_TAG" {
  default = "dev"
}

group "default" {
  targets = ["root", "python"]
}

target "_common" {
  platforms = ["linux/amd64", "linux/arm64", "linux/arm/v7"]
  output    = ["type=image,rewrite-timestamp=true"]
  args = {
    SOURCE_DATE_EPOCH = SOURCE_DATE_EPOCH
  }
}

target "root" {
  inherits = ["_common"]
  context  = "root"
  tags     = ["${REGISTRY}/${ROOT_PACKAGE}:${ROOT_TAG}"]
}

target "python" {
  inherits = ["_common"]
  context  = "python"
  tags     = ["${REGISTRY}/${PYTHON_PACKAGE}:${PYTHON_TAG}"]
  contexts = {
    parent = ROOT_DIGEST == "" ? "target:root" : "docker-image://${REGISTRY}/${ROOT_PACKAGE}:${ROOT_TAG}@${ROOT_DIGEST}"
  }
  labels = {
    "org.opencontainers.image.base.name"   = "${REGISTRY}/${ROOT_PACKAGE}:${ROOT_TAG}"
    "org.opencontainers.image.base.digest" = ROOT_DIGEST
  }
}
