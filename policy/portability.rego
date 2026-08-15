package main

import rego.v1

deny contains msg if {
  input.kind == "Deployment"
  some container in input.spec.template.spec.containers
  contains(container.image, "amazonaws.com")
  msg := sprintf("硬編碼 registry 位址不可攜: %s", [container.image])
}
