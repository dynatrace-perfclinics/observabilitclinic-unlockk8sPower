#   Mastering Kubernetes Resiliency   with Dynatrace: Avoiding Pitfalls, Optimizing and Auto-scaling Workloads
This repository contains all the files used during the demo of the Observability clinic:  Mastering Kubernetes Resiliency   with Dynatrace: Avoiding Pitfalls, Optimizing and Auto-scaling Workloads

This repository showcase the usage of the different worflow useful for platform engineers
* Dynatrace
* Kuma
* Kyberno

We will send all Telemetry data produced by otel-demo to Dynatrace.

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
NAME=isitobservable-otel-logs
gcloud container clusters create ${NAME} --zone=${ZONE} --machine-type=e2-standard-4 --num-nodes=2
```

## Getting started
### Dynatrace Tenant
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
### Edge Connect
1. Install EdgeConnect Management
in Dynatrace type `Ctrl+K` , and search for `EdgeConect`.
Click on INstall EdgeConnect Management.

3. Create a new EdgeConnect
Open The `EdgeConnect Management` Application, 
<p align="center"><img src="/image/edge_connect_connection.png" width="40%" alt="data token" /></p>

Once opened click on `+ New Edgeconnect`
<p align="center"><img src="/image/create_edgeconnect.png" width="40%" alt="data token" /></p>
Give a name and save into the following Environment variable:

```shell
EDGECONNECT_NAME=<YOUR EDGE CONNECT NAME>
```
Give a domain name to your EdgeConnect ( is does need to exist).

3. Save Oauth details
once the EdgeConnect create , Dynatrace will provide Oauth connection details:
<p align="center"><img src="/image/edgeconnect_secret.png" width="40%" alt="data token" /></p>

Save all the information into the following Environment variables:
```shell
EDGECONNECT_CLIENTID=<YOUR EDGE CONNECT CLIENT ID>
EDGECONNECT_CLIENTSECRET=<YOUR EDGE CONNECT CLIENT SECRET>
EDGECONNECT_CLIENTRESOURCE=<YOUR EDGE CONNECT CLIENT RESOURCE>
EDGECONNECT_TENANT_URL=<YOUT DYNATRACE APP TENANT URL>
```


### Kuma

1. Download kumactl
```shell
curl -L https://kuma.io/installer.sh | VERSION=2.5.0 sh -
```
This command download the latest version of istio ( in our case istio 1.18.2) compatible with our operating system.
2. Add istioctl to you PATH
```shell
cd kuma-2.5.0/bin
```
this directory contains samples with addons . We will refer to it later.
```shell
export PATH=$PWD/bin:$PATH
```

### Clone the Github Repository
```shell
https://github.com/dynatrace-perfclinics/observabilitclinic-unlockk8sPower
cd observabilitclinic-unlockk8sPower
```

### Deploy most of the components
The application will deploy the entire environment:
```shell
chmod 777 deployment.sh
./deployment.sh  --clustername "${NAME}" --edgename "${EDGECONNECT_NAME}" --edgeclientid "${EDGECONNECT_CLIENTID}" --edgesecret "${EDGECONNECT_CLIENTSECRET}" --edgeresource "${EDGECONNECT_CLIENTRESOURCE}" --edgetenanturl "${EDGECONNECT_TENANT_URL}" --dturl "${DT_TENANT_URL}" --dtingesttoken "${DATA_INGEST_TOKEN}" --dtoperatortoken "${API_TOKEN}" 
```
