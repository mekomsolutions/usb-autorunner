#!/usr/bin/env bash

kubectl="/usr/local/bin/k3s kubectl"
# Get NFS IP address
registry_ip=`$kubectl get svc registry-service -o json | jq '.spec.loadBalancerIP' | tr -d '"'`
# Get USB mount point
usb_mount_point=`grep "mount_point" /opt/autorunner/usbinfo | cut -d'=' -f2 | tr -d '"'`
echo "ℹ️ Archives will be saved in '${usb_mount_point}'"
sysinfo_folder=${usb_mount_point}/sysinfo
mkdir -p ${sysinfo_folder}

echo "⚙️  Running 'ps'"
ps aux > ${sysinfo_folder}/master1_processes.txt
echo "⚙️  Running 'top'"
top -n 1 > ${sysinfo_folder}/top.txt

echo "⚙️  Get clock info"
echo "Hardware time: '$(hwclock -r)'" > ${sysinfo_folder}/time.txt
echo "System time: '$(date)'" >> ${sysinfo_folder}/time.txt

echo "⚙️  Ping the RPi nodes"
ping 10.0.90.11 -c 4 -W 3 > ${sysinfo_folder}/ping_worker1.txt
ping 10.0.90.12 -c 4 -W 3 > ${sysinfo_folder}/ping_worker2.txt

echo "⚙️  kubectl get nodes"
$kubectl get nodes -o json > ${sysinfo_folder}/nodes.json
echo "⚙️  kubectl get services"
$kubectl get svc -o json > ${sysinfo_folder}/services.json
echo "⚙️  kubectl get deployment"
$kubectl get deployment.apps -o json > ${sysinfo_folder}/deployments.json
echo "⚙️  kubectl get statefulsets"
$kubectl get statefulsets.apps -o json > ${sysinfo_folder}/statefulsets.json
echo "⚙️  kubectl get pods"
$kubectl get pods -o json > ${sysinfo_folder}/pods.json
echo "⚙️  kubectl get jobs"
$kubectl get jobs -o json > ${sysinfo_folder}/jobs.json
echo "⚙️  kubectl get pv"
$kubectl get pv -o json > ${sysinfo_folder}/pv.json
echo "⚙️  kubectl get pvc"
$kubectl get pvc -o json > ${sysinfo_folder}/pvc.json
$kubectl get pods -n rsyslog -o json > ${sysinfo_folder}/rsyslog_pods.json

echo "⚙️  kubectl describe nodes"
$kubectl describe nodes > ${sysinfo_folder}/nodes.txt
echo "⚙️  kubectl describe deployment"
$kubectl describe deployment.apps > ${sysinfo_folder}/deployments.txt
echo "⚙️  kubectl describe services"
$kubectl describe deployment.apps > ${sysinfo_folder}/services.txt
echo "⚙️  kubectl describe statefulset"
$kubectl describe statefulset.apps > ${sysinfo_folder}/statefulsets.txt
echo "⚙️  kubectl describe jobs"
$kubectl describe jobs > ${sysinfo_folder}/jobs.txt
echo "⚙️  kubectl describe pods"
$kubectl describe pods > ${sysinfo_folder}/pods.txt
echo "⚙️  kubectl describe rsyslog pods"
$kubectl describe pods -n rsyslog > ${sysinfo_folder}/rsyslog_pods.txt

echo "✅ Done."
