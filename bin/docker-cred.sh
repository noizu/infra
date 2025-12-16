
kubectl create secret docker-registry ops-docker-registry-secret \
  --docker-server=ops.noizu.com \
  --docker-username=$NOIZU_REGISTRY_USER \
  --docker-password=$NOIZU_REGISTRY_PASSWORD \
  --docker-email=$DOCKER_USER \
  --namespace=trl-wp
#  ---

  kubectl create secret docker-registry docker-registry-secret \
  --docker-server=docker.io \
  --docker-username=$DOCKER_USER \
  --docker-password=$DOCKER_PASSWORD \
  --docker-email=$DOCKER_USER \
  --namespace=trl-wp 

  kubectl create secret docker-registry nb-registry-secret \
  --docker-server=docker.io \
  --docker-username=$DOCKER_USER \
  --docker-password=$DOCKER_PASSWORD \
  --docker-email=$DOCKER_USER \
  --namespace=trl-wp


  # ---



#kubectl patch serviceaccount default \
#  -p '{"imagePullSecrets": [{"name": "docker-registry-secret"},{"name": "ops-docker-registry-secret"}]}'  -n default


#kubectl patch serviceaccount default \
#  -p '{"imagePullSecrets": [{"name": "docker-registry-secret"},{"name": "ops-docker-registry-secret"},{"name": "nb-registry-secret"}]}' \
#  -n nlb

kubectl patch serviceaccount default \
  -p '{"imagePullSecrets": [{"name": "docker-registry-secret"},{"name": "ops-docker-registry-secret"}]}'  -n trl-wp
