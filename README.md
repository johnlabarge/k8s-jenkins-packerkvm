README
======

This is a multipart tutorial which shows how to setup jenkins on kubernetes.
The thing that makes this especially interesting is the requirement is to 
* use an existing jenkins agent running in GKE.
* use of jenkins to spin up packer builds.
* the packer builds depend on qemu-kvm.

Approach
------------------------

The approach used is use jenkins to spin up compute instances on demand to execute packer builds.
The tutorial walks you through the steps of setting up each component 

Provision a GKE cluster 
------------------------
### Login to your GCP, set the project of choice, open cloud shell:

[![button](http://gstatic.com/cloudssh/images/open-btn.png)](https://console.cloud.google.com/cloudshell/open?git_repo=https://github.com/johnlabarge/k8s-jenkins-packerkvm&page=editor&tutorial=README.md)


### Task 1: Create the GKE cluster 
```sh 
VERSION=$(gcloud container get-server-config --zone us-central1-c --format='value(validMasterVersions[0])')
gcloud container clusters create dev --zone=us-central1-c \
--cluster-version=${VERSION} \
--machine-type n1-standard-2 \
--num-nodes 2 \
--scopes='https://www.googleapis.com/auth/projecthosting,storage-rw,cloud-platform'
```

### Task 2: Install helm
1. Download and install helm:
```sh 
wget https://storage.googleapis.com/kubernetes-helm/helm-v2.9.1-linux-amd64.tar.gz
tar zxfv helm-v2.9.1-linux-amd64.tar.gz
cp linux-amd64/helm .
```
1. Add yourself as the cluster admin:
```sh
kubectl create clusterrolebinding cluster-admin-binding --clusterrole=cluster-admin \
--user=$(gcloud config get-value account)
```

2. Grant tiller the service of the helm HELM the cluster-admin:
```sh
    kubectl create serviceaccount tiller --namespace kube-system
    kubectl create clusterrolebinding tiller-admin-binding --clusterrole=cluster-admin \
               --serviceaccount=kube-system:tiller
```               

3. Initialize helm:
```sh
./helm init --service-account=tiller
./helm update
```

1. Ensure helm is properly installed:
```sh
./helm version
```

### Task 3: Install Jenkins

1. Create Jenkins Configuraiton
```sh
cat <<CONFIG >values.yaml
Master:
  InstallPlugins:
    - kubernetes:1.7.1
    - workflow-aggregator:2.5
    - workflow-job:2.21
    - credentials-binding:1.16
    - git:3.9.1
    - google-oauth-plugin:0.6
    - google-source-plugin:0.3
    - google-compute-engine:1.0.4 
    - google-storage-plugin:1.2
    - jclouds-jenkins:2.14
  Cpu: "1"
  Memory: "3500Mi"
  JavaOpts: "-Xms3500m -Xmx3500m"
  ServiceType: ClusterIP
Agent:
  Enabled: false
Persistence:
  Size: 100Gi
NetworkPolicy:
  ApiVersion: networking.k8s.io/v1
rbac:
  install: true
  serviceAccountName: cd-jenkins
CONFIG
```
1. Install Jenkins
```sh
    ./helm install -n cd stable/jenkins -f values.yaml --version 0.16.6 --wait
```
2. Get the Admin password.
```sh 
    printf $(kubectl get secret --namespace default cd-jenkins -o jsonpath="{.data.jenkins-admin-password}" | base64 --decode);echo
```
3. Wait for jenkins pod to come up
```sh
kubectl get pods --watch 
```
4. Get the Jenkins URL to visit by running these commands in the same shell:
```sh
export POD_NAME=$(kubectl get pods --namespace default -l "component=cd-jenkins-master" -o jsonpath="{.items[0].metadata.name}")
  echo http://127.0.0.1:8080
  kubectl port-forward $POD_NAME 8080:8080
```

1. Install plugins: 
On the jenkins site-> Manage - > 
Check for intalled plugins. Ensure you have compute engine/storage bucket plugins


### Building jenkins agent image
The jenkins agent image needs to have 
* nested virtualization
* packer
* qemu-kvm
* jenkins agent

### Service Account Creation 
1. Create the service account
```sh 
gcloud iam service-accounts create jenkins --display-name jenkins
```

1. Store the service account email
```sh
export SA_EMAIL=$(gcloud iam service-accounts list \
    --filter="displayName:jenkins" --format='value(email)')
export PROJECT=$(gcloud info --format='value(config.project)')
```

1. Add iam roles to service account
```sh 
gcloud projects add-iam-policy-binding $PROJECT \
    --role roles/storage.admin --member serviceAccount:$SA_EMAIL
gcloud projects add-iam-policy-binding $PROJECT --role roles/compute.instanceAdmin.v1 \
    --member serviceAccount:$SA_EMAIL
gcloud projects add-iam-policy-binding $PROJECT --role roles/compute.networkAdmin \
    --member serviceAccount:$SA_EMAIL
gcloud projects add-iam-policy-binding $PROJECT --role roles/compute.securityAdmin \
    --member serviceAccount:$SA_EMAIL
gcloud projects add-iam-policy-binding $PROJECT --role roles/iam.serviceAccountActor \
    --member serviceAccount:$SA_EMAIL
```

1. Create the service account key
```sh 
gcloud iam service-accounts keys create jenkins-sa.json --iam-account $SA_EMAIL
```
1. Copy the result of the command ``echo "$(pwd)/jenkins-sa.json"`` to the clipboard
1. In cloud shell click the More button  ![more button](jenkins-ce-cloud-shell-more.png)
1. Click **Download file**
1. Paste the copied contents into the text box. 
1. Click **Download** to save the file locally.

### Nested Virtualization Image
Start with with a standard centos-7 image (us-central1-b has the default mincpu platform to be haswell, hence this example uses haswell since that min platform is required to turn nested virt on) 
```sh
    gcloud compute disks create disk1 \
        --image-project centos-cloud \
        --image-family centos-7 \
        --zone us-central1-b

    gcloud compute images create nested-vzn-image \
        --source-disk disk1 \
        --source-disk-zone us-central1-b \
        --licenses "https://www.googleapis.com/compute/v1/projects/vm-options/global/licenses/enable-vmx"
```        
### Create the Jenkins Agent 
1. Download and unpack Packer 
```sh
wget https://releases.hashicorp.com/packer/0.12.3/packer_0.12.3_linux_amd64.zip
unzip packer_0.12.3_linux_amd64.zip
```
1. Create the agent configuration using packer 
```sh
export PROJECT=$(gcloud info --format='value(config.project)')
cat > jenkins-agent.json <<EOF
{
  "builders": [
    {
      "type": "googlecompute",
      "project_id": "$PROJECT",
      "source_image": "nested-vzn-image"
      "zone": "us-central1-a",
      "disk_size": "10",
      "image_name": "jenkins-agent-{{timestamp}}",
      "image_family": "jenkins-agent",
      "ssh_username": "ubuntu"
      "startup_script_file": "agent_install.sh" 
    }
  ],
  "provisioners": [
    {
      "type": "shell",
      "inline": ["sudo apt-get update",
                  "sudo apt-get install -y default-jdk"]
    }
  ]
}
EOF
```
2. Build the agent image using packer
```sh
./packer build jenkins-agent.json
``` 

### Jenkins configuration
TODO WIP
1. Goto **Jenkins->configuration->**
1. Scroll down to the end of the page and **"Add a Google Compute Engine"**
1. Give it a good name and set the project id appropriately, set the service account credentials that allows GCE api calls.
I set a label called "jenkins-qemu" to ensure jobs needing nested virt land on the instances backed by this configuration. 
Set the zone to us-central1-b since the minCpuPlatform is "Haswell"
Check "External IP" for networking.
Set the Bootdisk image to be the image nested-centos-jenkins.

###Create a Jenkins Job:

Source Repo: Point it to your packer build repo 
eg.

Build: 
packerio build *.json

Postbuild Actions:
Classic Upload:
file pattern: output/*image 
storage location: gs://imagestorerk (pre-created bucket)

Set "Restrict where this project can be run":
set to jenkins-qemu



References
----------

* [packer-openstack-centos-image](https://github.com/jkhelil/packer-openstack-centos-image)
* [Packer Image Builder for RHEL Family (RedHat, CentOS, Oracle Linux)](https://github.com/TelekomLabs/packer-rhel)
* [Enabling nested virtualization on an instance](https://cloud.google.com/compute/docs/instances/enable-nested-virtualization-vm-instances#enablenestedvirt)
