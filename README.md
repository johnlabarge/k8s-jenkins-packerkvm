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
###Login to your GCP, set the project of choice, open cloud shell:

    gcloud container clusters create jenkins-cd   --network default --machine-type n1-standard-2 --num-nodes 2   --scopes "http
s://www.googleapis.com/auth/projecthosting,storage-rw,cloud-platform"  --zone=us-central1-b

###Install helm
Download and install helm:
    wget https://storage.googleapis.com/kubernetes-helm/helm-v2.9.1-linux-amd64.tar.gz
    tar zxfv helm-v2.9.1-linux-amd64.tar.gz
    cp linux-amd64/helm .

Add yourself as the cluster admin:
    kubectl create clusterrolebinding cluster-admin-binding --clusterrole=cluster-admin \
        --user=$(gcloud config get-value account)

Grant tiller the servide of the helm HELM the cluster-admin:
    kubectl create serviceaccount tiller --namespace kube-system
    kubectl create clusterrolebinding tiller-admin-binding --clusterrole=cluster-admin \
               --serviceaccount=kube-system:tiller
               
Initialize helm:
    ./helm init --service-account=tiller
    ./helm update

Ensure helm is properly installed:
    ./helm version

References:
[1]https://cloud.google.com/solutions/jenkins-on-kubernetes-engine-tutorial


###Jenkins
Install:
    ./helm install -n cd stable/jenkins -f jenkins/values.yaml --version 0.16.6 --wait

Admin password:
    printf $(kubectl get secret --namespace default cd-jenkins -o jsonpath="{.data.jenkins-admin-password}" | base64 --decode);echo

Get the Jenkins URL to visit by running these commands in the same shell:
  export POD_NAME=$(kubectl get pods --namespace default -l "component=cd-jenkins-master" -o jsonpath="{.items[0].metadata.name}")
  echo http://127.0.0.1:8080
  kubectl port-forward $POD_NAME 8080:8080

Install plugins: 
On the jenkins site-> Manage - > 
Check for intalled plugins. Ensure you have compute engine/storage bucket plugins


References:
[1]https://cloud.google.com/solutions/jenkins-on-container-engine

### Building jenkins agent image
The jenkins agent image needs to have 
* nested virtualization
* packer
* qemu-kvm
* jenkins agent

Start with with a standard centos-7 image (us-central1-b has the default mincpu platform to be haswell, hence this example uses haswell since that min platform is required to turn nested virt on) 

    gcloud compute disks create disk1 \
        --image-project centos-cloud \
        --image-family centos-7 \
        --zone us-central1-b

    gcloud compute images create nested-vm-image \
        --source-disk disk1 \
        --source-disk-zone us-central1-b \
        --licenses "https://www.googleapis.com/compute/v1/projects/vm-options/global/licenses/enable-vmx"

Create the GCE VM:

    gcloud compute instances create packer-build-host \
        --zone us-central1-b \
        --machine-type=n1-standard-4 \
        --boot-disk-size=20GB \
        --boot-disk-type=pd-ssd \
        --image nested-vm-image


SSH to the GCE VM:

    gcloud compute ssh packer-build-host --zone=us-central1-b


Install packages required 
   
Install QEMU/KVM:

    sudo -i

    yum install qemu-kvm unzip git

Packer needs __qemu-kvm__ available in the BASH path. For some reason it isn't added. Add it:

    echo 'export PATH=$PATH:/usr/libexec' > /etc/profile.d/libexec-path.sh

    source /etc/profile.d/libexec-path.sh

Also, add __/usr/local/bin__ to your BASH path:

    echo 'export PATH=$PATH:/usr/local/bin' > /etc/profile.d/usr-local-bin-path.sh

    source /etc/profile.d/usr-local-bin-path.sh

Download the [latest version of Packer](https://www.packer.io/downloads.html):

    curl -O https://releases.hashicorp.com/packer/1.3.0/packer_1.3.0_linux_amd64.zip

Unzip __packer__:

    unzip packer_1.3.0_linux_amd64.zip

There's already a program named __packer__ in the BASH path. Do not remove this program as it is part of the __cracklib-dicts__ package which many other programs depend on. Instead, rename the __packer__ program you just downloaded to __packerio__:

    mv packer /usr/local/bin/packerio


Install Java libraries for Jenkins agent:

    sudo yum install java-1.8.0-openjdk-devel -y
    sudo yum install java-1.7.0-openjdk -y

Build the image:
    sudo shutdown -h now

Create an image from the disk from the VM just shutdown above nested-centos-jenkins

This image will be used for further Jenkins setup

###Jenkins configuration

Configuration:
Goto Jenkins->configuration->:
Scroll down to the end of the page and "Add a Google Compute Engine"
Give it a good name and set the project id appropriately, set the service account credentials that allows GCE api calls.
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


Prepare the Image for Upload
----------------------------

The resulting image is usually larger than it needs to be. It can be compressed using the `qemu-img` command.

For example, start by changing into the output directory for the particular image built by `packer`:

    cd output-centos-7-x86_64-1611-ext4

Then, compress the image:

    qemu-img convert -c centos-7-x86_64-1611-ext4 -O qcow2 centos-7-x86_64-1611-ext4.qcow2

References
----------

* [packer-openstack-centos-image](https://github.com/jkhelil/packer-openstack-centos-image)
* [Packer Image Builder for RHEL Family (RedHat, CentOS, Oracle Linux)](https://github.com/TelekomLabs/packer-rhel)
* [Enabling nested virtualization on an instance](https://cloud.google.com/compute/docs/instances/enable-nested-virtualization-vm-instances#enablenestedvirt)
