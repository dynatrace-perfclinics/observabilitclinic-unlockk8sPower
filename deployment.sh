#!/usr/bin/env bash

################################################################################
### Script deploying the Observ-K8s environment
### Parameters:
### dttoken: Dynatrace api token with ingest metrics and otlp ingest scope
### dturl : url of your DT tenant wihtout any / at the end for example: https://dedede.live.dynatrace.com
################################################################################


### Pre-flight checks for dependencies
if ! command -v jq >/dev/null 2>&1; then
    echo "Please install jq before continuing"
    exit 1
fi

if ! command -v git >/dev/null 2>&1; then
    echo "Please install git before continuing"
    exit 1
fi


if ! command -v helm >/dev/null 2>&1; then
    echo "Please install helm before continuing"
    exit 1
fi

if ! command -v kubectl >/dev/null 2>&1; then
    echo "Please install kubectl before continuing"
    exit 1
fi
echo "parsing arguments"
while [ $# -gt 0 ]; do
  case "$1" in
   --dtoperatortoken)
   DTOPERATORTOKEN="$2"
    shift 2
       ;;
   --dtingesttoken)
   DTTOKEN="$2"
   shift 2
     ;;
   --dturl)
   DTURL="$2"
   shift 2
     ;;
   --clustername)
   CLUSTERNAME="$2"
   shift 2
    ;;
    --edgename)
    EDGE_NAME="$2"
    shift 2
     ;;
     --edgeclientid)
     EDGE_CLIENTID="$2"
     shift 2
      ;;
     --edgesecret)
     EDGE_CLIENTSECRET="$2"
     shift 2
      ;;
    --edgeresource
     EDGE_CLIENTRESOURCE="$2"
     shift 2
      ;;
    --edgetenanturl
     EDGE_TENANTURL="$2"
     shift 2
      ;;
  *)
    echo "Warning: skipping unsupported option: $1"
    shift
    ;;
  esac
done


echo "Checking arguments"
if [ -z "$CLUSTERNAME" ]; then
  echo "Error: clustername not set!"
  exit 1
fi
if [ -z "$DTURL" ]; then
  echo "Error: Dt url not set!"
  exit 1
fi

if [ -z "$DTTOKEN" ]; then
  echo "Error: Data ingest api-token not set!"
  exit 1
fi

if [ -z "$DTOPERATORTOKEN" ]; then
  echo "Error: DT operator token not set!"
  exit 1
fi
if [ -z "$EDGE_NAME" ]; then
  echo "Error: edge connect name not set!"
  exit 1
fi
if [ -z "$EDGE_CLIENTID" ]; then
  echo "Error: Oaut client id not set!"
  exit 1
fi
if [ -z "$EDGE_CLIENTSECRET" ]; then
  echo "Error: Oauth client secret  not set!"
  exit 1
fi
if [ -z "$EDGE_CLIENTRESOURCE" ]; then
  echo "Error: Edge client resource not set!"
  exit 1
fi
if [ -z "$EDGE_TENANTURL" ]; then
  echo "Error: Edge tenant url not set!"
  exit 1
fi

#### Deploy the cert-manager
echo "Deploying Cert Manager ( for OpenTelemetry Operator)"
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.10.0/cert-manager.yaml
# Wait for pod webhook started
kubectl wait pod -l app.kubernetes.io/component=webhook -n cert-manager --for=condition=Ready --timeout=2m
# Deploy the opentelemetry operator
sleep 10
echo "Deploying the OpenTelemetry Operator"
kubectl apply -f https://github.com/open-telemetry/opentelemetry-operator/releases/latest/download/opentelemetry-operator.yaml
sleep 10

kubectl create secret generic dynatrace  --from-literal=dynatrace_oltp_url="$DTURL" --from-literal=dt_api_token="$DTTOKEN"
kubectl apply -f openTelemetry/rbac.yaml
kubectl apply -f openTelemetry/openTelemetry-manifest_debut_transform.yaml

kumactl install control-plane \
  --set "controlPlane.mode=standalone" \
  --set "controlPlane.tracing.openTelemetry.endpoint=oteld-collector.default.svc.cluster.local:4317" \
  | kubectl apply -f -

#deploy demo application
kubectl create ns otel-demo
kubectl label ns otel-demo kuma.io/sidecar-injection=enabled
kubectl label ns otel-demo oneagent=false
kubectl apply -f kuma/gatewayinstance.yaml -n otel-demo

### get the ip adress of ingress ####
IP=""
while [ -z $IP ]; do
  echo "Waiting for external IP"
  IP=$(kubectl get svc -n otel-demo edge-gateway -ojson | jq -j '.status.loadBalancer.ingress[].ip')
  [ -z "$IP" ] && sleep 10
done
echo 'Found external IP: '$IP
sed -i "s,IP_TO_REPLACE,$IP," openTelemetry/deployment.yaml
sed -i "s,IP_TO_REPLACE,$IP," kuma/gateway.yaml

kubectl create namespace dynatrace
kubectl apply -f https://github.com/Dynatrace/dynatrace-operator/releases/download/v0.14.2/kubernetes.yaml
kubectl apply -f https://github.com/Dynatrace/dynatrace-operator/releases/download/v0.14.2/kubernetes-csi.yaml
kubectl -n dynatrace wait pod --for=condition=ready --selector=app.kubernetes.io/name=dynatrace-operator,app.kubernetes.io/component=webhook --timeout=300s
kubectl -n dynatrace create secret generic dynakube --from-literal="apiToken=$DTOPERATORTOKEN" --from-literal="dataIngestToken=$DTTOKEN"
sed -i "s,TENANTURL_TOREPLACE,$DTURL," dynatrace/dynakube.yaml
sed -i "s,CLUSTER_NAME_TO_REPLACE,$CLUSTERNAME,"  dynatrace/dynakube.yaml
kubectl apply -f dynatrace/dynakube.yaml -n dynatrace


kubectl apply -f openTelemetry/deployment.yaml -n otel-demo
kubectl apply -f kuma/gateway.yaml
kubectl apply -f kuma/MeshAccesslog.yaml
kubectl apply -f kuma/meshtrace.yaml

kubectl create ns hipster-shop
kubectl label ns hipster-shop kuma.io/sidecar-injection=enabled
kubectl label ns hipster-shop oneagent=true
kubectl create secret generic dynatrace  --from-literal=dynatrace_oltp_url="$DTURL" --from-literal=dt_api_token="$DTTOKEN" -n hipster-shop
kubectl apply -f hipster-shop/k8s-manifest.yaml -n hipster-shop


helm repo add kyverno https://kyverno.github.io/kyverno/
helm repo add falcosecurity https://falcosecurity.github.io/charts
helm repo update
kubectl create ns kyverno
helm install kyverno-policies kyverno/kyverno -n kyverno -f kyberno/value.yaml


kubectl create namespace falco
helm install falco -n falco --set driver.kind=ebpf --set tty=true falcosecurity/falco \
--set falcosidekick.enabled=true \
--set falcosidekick.config.slack.webhookurl=$(base64 --decode <<< "aHR0cHM6Ly9ob29rcy5zbGFjay5jb20vc2VydmljZXMvVDA0QUhTRktMTTgvQjA1SzA3NkgyNlMvV2ZHRGQ5MFFDcENwNnFzNmFKNkV0dEg4") \
--set falcosidekick.config.slack.minimumpriority=notice \
--set falcosidekick.config.customfields="user:changeme" \
--set falco.grpc.enabled=true \
--set falco.grpc_output.enabled=true

kubectl  create secret -n dynatrace  generic edgeconnect-oauth --from-literal="oauth-client-id=$EDGE_CLIENTID" --from-literal="oauth-client-secret=$EDGE_CLIENTSECRET"
sed -i "s,EDGE_NAME_TO_REPLACE,$EDGE_NAME,"  dynatrace/edgeconnect.yaml
sed -i "s,TENANT_ULR_REPLACE,$EDGE_TENANTURL,"  dynatrace/edgeconnect.yaml
sed -i "s,CLIENT_RESSOURCE_TO_REPLACE,$EDGE_CLIENTRESOURCE,"  dynatrace/edgeconnect.yaml
kubectl apply -f dynatrace/edgeconnect.yaml -n dynatrace
kubectl apply -f dynatrace/configmap.yaml -n dynatrace