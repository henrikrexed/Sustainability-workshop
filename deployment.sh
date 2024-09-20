#!/usr/bin/env bash

################################################################################
### Script deploying the Observ-K8s environment
### Parameters:
### Clustern name: name of your k8s cluster
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


#### Deploy the cert-manager
echo "Deploying Cert Manager ( for OpenTelemetry Operator)"
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.10.0/cert-manager.yaml
# Wait for pod webhook started
kubectl wait pod -l app.kubernetes.io/component=webhook -n cert-manager --for=condition=Ready --timeout=2m
# Deploy the opentelemetry operator
sleep 10
echo "Deploying the OpenTelemetry Operator"
kubectl apply -f https://github.com/open-telemetry/opentelemetry-operator/releases/latest/download/opentelemetry-operator.yaml

# Add Kepler



#Add kubegreen
echo "Deploying Kubegreen"
kubectl apply -f https://github.com/kube-green/kube-green/releases/latest/download/kube-green.yaml

##add keptn metrics
helm repo add keptn https://charts.lifecycle.keptn.sh
helm repo update
helm upgrade --install keptn keptn/keptn -n keptn-system --create-namespace --wait

##ad argo Workflow
helm repo add argo https://argoproj.github.io/argo-helm
helm install argo argo/argo-workflows --create-namespace  -n argo -f argo/values.yaml
kubectl apply -f argo/plugin.yaml
kubectl apply -f argo/token.yaml -n argo
kubectl apply -f https://raw.githubusercontent.com/bacherfl/argo-keptn-plugin/main/config/rbac.yaml

helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm install prometheus prometheus-community/kube-prometheus-stack   \
  --namespace prometheus --create-namespace \
  --set alertmanager.enabled=false  --wait

echo "Deploying Kepler"
helm repo add kepler https://sustainable-computing-io.github.io/kepler-helm-chart
helm install kepler kepler/kepler \
    --namespace kepler \
    --create-namespace \
    --set serviceMonitor.enabled=true \
    --set serviceMonitor.labels.release=prometheus \
    --set canMount.usrSrc=false
kubectl wait pod --namespace prometheus -l "release=prometheus" --for=condition=Ready --timeout=2m
PROMETHEUS_SERVER=$(kubectl get svc -l app=kube-prometheus-stack-prometheus -n prometheus -o jsonpath="{.items[0].metadata.name}")
sed -i "s,PROMETHEUS_SERVER_TO_REPLACE,$PROMETHEUS_SERVER," keptn/keptnmetricProvider.yaml
#Deploy istio
istioctl install -f istio/istio-operator.yaml --skip-confirmation

#### Deploy the Dynatrace Operator
echo "Deploying Dynatrace operator"
kubectl create namespace dynatrace
kubectl apply -f https://github.com/Dynatrace/dynatrace-operator/releases/download/v1.2.2/kubernetes.yaml
kubectl apply -f https://github.com/Dynatrace/dynatrace-operator/releases/download/v1.2.2/kubernetes-csi.yaml
kubectl -n dynatrace wait pod --for=condition=ready --selector=app.kubernetes.io/name=dynatrace-operator,app.kubernetes.io/component=webhook --timeout=300s
kubectl -n dynatrace create secret generic dynakube --from-literal="apiToken=$DTOPERATORTOKEN" --from-literal="dataIngestToken=$DTTOKEN"
sed -i "s,TENANTURL_TOREPLACE,$DTURL," dynatrace/dynakube.yaml
sed -i "s,TENANTURL_TOREPLACE,$DTURL," keptn/keptnmetricProvider.yaml
sed -i "s,CLUSTER_NAME_TO_REPLACE,$CLUSTERNAME,"  dynatrace/dynakube.yaml
kubectl apply -f dynatrace/dynakube.yaml -n dynatrace
### get the ip adress of ingress ####
IP=""
while [ -z $IP ]; do
  echo "Waiting for external IP"
  IP=$(kubectl get svc istio-ingressgateway -n istio-system -ojson | jq -j '.status.loadBalancer.ingress[].ip')
  [ -z "$IP" ] && sleep 10
done
echo 'Found external IP: '$IP
sed -i "s,IP_TO_REPLACE,$IP," opentelemetry/deploy_1_11.yaml
sed -i "s,IP_TO_REPLACE,$IP," istio/istio_gateway.yaml
sed -i "s,IP_TO_REPLACE,$IP," hipstershop/k8s-manifest.yaml

# Deploy collector
echo "Deploying the collector"
kubectl create secret generic dynatrace  --from-literal=dynatrace_oltp_url="$DTURL" --from-literal=clustername="$CLUSTERNAME"  --from-literal=clusterid=$CLUSTERID  --from-literal=dt_api_token="$DTTOKEN"
kubectl apply -f opentelemetry/rbac.yaml
kubectl apply -f opentelemetry/openTelemetry-manifest_statefulset.yaml
kubectl apply -f opentelemetry/openTelemetry-manifest_ds.yaml

#deploy demo application
echo "Deploying hipster-shop"
kubectl create ns hipster-shop
kubectl label namespace hipster-shop istio-injection=enabled
kubectl label namespace hipster-shop oneagent=true
kubectl annotate ns hipster-shop  keptn.sh/lifecycle-toolkit="enabled"
kubectl create secret generic dynatrace  --from-literal=dynatrace_oltp_url="$DTURL" --from-literal=dt_api_token="$DTTOKEN" -n hipster-shop
kubectl apply -f hipstershop/k8s-manifest.yaml -n hipster-shop

#Deploy oteldemo
echo "Deploying oteldemo"
kubectl create ns otel-demo
kubectl label namespace otel-demo istio-injection=enabled
kubectl label namespace otel-demo oneagent=false
kubectl apply -f opentelemetry/deploy_1_11.yaml -n otel-demo


kubectl annotate --overwrite pod --all -n kube-green \
metrics.dynatrace.com/port='8080' metrics.dynatrace.com/scrape='true' \
metrics.dynatrace.com/filter='{
    "mode": "include",
    "names": [
      "kube_green_current_sleepinfo"
    ]
  }'
kubectl apply -f istio/istio_gateway.yaml

kubectl apply -f keptn/keptnmetricProvider.yaml -n hipster-shop
kubectl apply -f keptn/keptnTask.yaml -n hipster-shop
kubectl apply -f keptn/keptnTask.yaml -n hipster-shop
kubectl apply -f keptn/KeptnAnalysis.yaml -n hipster-shop
kubectl apply -f keptn/KeptnAnalysis.yaml -n hipster-shop
kubectl apply -f keptn/analysisdefinition.yaml -n hipster-shop

echo "--------------Demo--------------------"
echo "url of the demo: "
echo "otel-demo : http://oteldemo.$IP.nip.io"
echo "hipstershop url: http://hipstershop.$IP.nip.io"
echo "========================================================"