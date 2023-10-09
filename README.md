# The Sustainability workshop
This repository contains all the files for the workshop around Sustainability

This repository showcase the usage of several feature of Dynatrace in the case of Sustainability using solution like : 
* Kepler
* KubeGreen


## Prerequisite 
The following tools need to be install on your machine :
- jq
- kubectl
- git
- gcloud ( if you are using GKE)
- Helm

### 1.Create a Google Cloud Platform Project
```shell
PROJECT_ID="<your-project-id>"
gcloud services enable container.googleapis.com --project ${PROJECT_ID}
gcloud services enable monitoring.googleapis.com \
cloudtrace.googleapis.com \
clouddebugger.googleapis.com \
cloudprofiler.googleapis.com \
--project ${PROJECT_ID}
```
### 2.Create a GKE cluster
```shell
ZONE=europe-west3-a
NAME=sustainabilty-workshop
gcloud container clusters create ${NAME} --zone=${ZONE} --machine-type=e2-standard-8 --num-nodes=2
```
### 3.Istio

1. Download Istioctl
```shell
curl -L https://istio.io/downloadIstio | sh -
```
This command download the latest version of istio ( in our case istio 1.18.2) compatible with our operating system.
2. Add istioctl to you PATH
```shell
cd istio-1.19.0
```
this directory contains samples with addons . We will refer to it later.
```shell
export PATH=$PWD/bin:$PATH
```

### 4.Clone Github repo
```shell
git clone https://github.com/henrikrexed/sustainability-workshop
cd sustainability-workshop
```


### 5. Dynatrace 
##### 1. Dynatrace Tenant - start a trial
If you don't have any Dynatrace tenant , then i suggest to create a trial using the following link : [Dynatrace Trial](https://bit.ly/3KxWDvY)
Once you have your Tenant save the Dynatrace (including https) tenant URL in the variable `DT_TENANT_URL` (for example : https://dedededfrf.live.dynatrace.com)
```shell
DT_TENANT_URL=<YOUR TENANT URL>
```
##### 2. Create the Dynatrace API Tokens
The dynatrace operator will require to have several tokens:
* Token to deploy and configure the various components
* Token to ingest metrics and Traces


###### Operator Token
One for the operator having the following scope:
* Create ActiveGate tokens
* Read entities
* Read Settings
* Write Settings
* Access problem and event feed, metrics and topology
* Read configuration
* Write configuration
* Paas integration - installer downloader
<p align="center"><img src="/image/operator_token.png" width="40%" alt="operator token" /></p>

Save the value of the token . We will use it later to store in a k8S secret
```shell
API_TOKEN=<YOUR TOKEN VALUE>
```
###### Ingest data token
Create a Dynatrace token with the following scope:
* Ingest metrics (metrics.ingest)
* Ingest logs (logs.ingest)
* Ingest events (events.ingest)
* Ingest OpenTelemetry
* Read metrics
<p align="center"><img src="/image/data_ingest_token.png" width="40%" alt="data token" /></p>
Save the value of the token . We will use it later to store in a k8S secret

```shell
DATA_INGEST_TOKEN=<YOUR TOKEN VALUE>
```

### 6. Run the deployment script
```shell
cd ..
chmod 777 deployment.sh
./deployment.sh  --clustername "${NAME}" --dturl "${DT_TENANT_URL}" --dtingesttoken "${DATA_INGEST_TOKEN}" --dtoperatortoken "${API_TOKEN}"
```
### 6. Deploy the Kepler Dashboard

in Dynatrace, Open the dashboard Application.
( Apps, and search for Dashboard)
<p align="center"><img src="/image/dashboard.png" width="40%" alt="data token" /></p>

Click on upload, and import the file  `dynatrace/Kepler.json`

you should see the following dashboard:
<p align="center"><img src="/image/kepler.png" width="40%" alt="data token" /></p>


### 7. Run the Query reporting unused namespaces
In dynatrace open The Notebooks application.
( Apps, search for Notebook)
Create a new Notebook, by pressing on the + button
<p align="center"><img src="/image/notebook.png" width="40%" alt="data token" /></p>

Run the following DQL :
```
fetch logs, from:-24h, to:-1h
| parse content ,"LD DQS:requestmethod LD:responsce_codes SPACE LD SPACE LD:type SPACE LD SPACE DQS SPACE  LD:byte_received SPACE LD:byte_sent SPACE LD:response_time SPACE LD:upstream_service_time SPACE DQS SPACE DQS:user_agent SPACE DQS:request_id SPACE DQS:upstream_host SPACE DQS:upstream_ip LD:rest"
| filter not  contains(requestmethod,"/opentelemetry.proto")
| filter requestmethod !="- - -"
| sort timestamp asc
| summarize count() , first=takeFirst(timestamp),last=takeLast(timestamp), by:{k8s.deployment.name, k8s.namespace.name}
| fieldsAdd fristts=toTimestamp(first), lastts=toTimestamp(last)
| fieldsAdd total=lastts-fristts
| fieldsadd totalduration=toDuration(total)
| filter totalduration < 3h and  totalduration > 1s
| summarize nsfirst=takeFirst(first), nslast=takeLast(last), by:{k8s.namespace.name}
```
This query will look at the access logs produced by Envoy and return all the namespaces having no request since a period of 3h.

### 8.Automate the configuration of the SleepInfo CRD of Kube-Green
To automate the configuration of your Sleepinfo CRD, we would upload in dynatrace the workload located in : `dynatrace/wf_configure_kubegreen_0ab8b83d-e3c4-4580-ba88-2ddf25c40f9a.json`
This workload used Slack, make sure to configure the [slack integration in dynatrace](https://www.dynatrace.com/support/help/platform-modules/cloud-automation/workflows/actions/slack).

To import the worklow, Open the Workflow application in dynatrace
( Apps, search for workflow), click on the upload button.
<p align="center"><img src="/image/workflow.png" width="40%" alt="data token" /></p>

This workflow is using a demo slack channel, make sure to update the workflow to use your own slack channel.

