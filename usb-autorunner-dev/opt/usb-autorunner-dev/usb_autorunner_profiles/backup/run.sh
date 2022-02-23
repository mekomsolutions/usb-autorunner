#!/usr/bin/env bash

kubectl="/usr/local/bin/k3s kubectl"

AUTORUNNER_WORKDIR=/opt/autorunner/workdir
OPENMRS_JOB_NAME=mysql-openmrs-db-backup
ODOO_JOB_NAME=postgres-odoo-db-backup
OPENELIS_JOB_NAME=postgres-openelis-db-backup
FILESTORE_JOB_NAME=filestore-data-backup
LOGGING_JOB_NAME=logging-data-backup

# Retrieve Docker registry IP address
echo "🗂  Retrieve Docker registry IP."
REGISTRY_IP=`$kubectl get svc registry-service -o json | jq '.spec.loadBalancerIP' | tr -d '"'`

# Sync images to registry
echo "⚙️  Upload container images to the registry at $REGISTRY_IP..."
skopeo sync --scoped --dest-tls-verify=false --src dir --dest docker $AUTORUNNER_WORKDIR/images/docker.io $REGISTRY_IP

# Get USB mount point
usb_mount_point=`grep "mount_point" /opt/autorunner/usbinfo | cut -d'=' -f2 | tr -d '"'`
backup_folder=${usb_mount_point}/backup-$(date +'%Y-%m-%d_%H-%M')/
echo "ℹ️ Archives will be saved in '${backup_folder}'"
mkdir -p $backup_folder
logs_folder=/mnt/disks/ssd1/logging

echo "⚙️  Delete old backup jobs"
$kubectl delete job -l app=usb-backup --ignore-not-found=true
$kubectl delete job -n rsyslog -l app=usb-backup --ignore-not-found=true

mkdir -p ${backup_folder}/filestore
echo "⚙️  Run Filestore backup job"
# Backup filestore
cat <<EOF | $kubectl apply -f -
apiVersion: batch/v1
kind: Job
metadata:
  name: "${FILESTORE_JOB_NAME}"
  labels:
    app: usb-backup
spec:
  template:
    spec:
      volumes:
        - name: data
          persistentVolumeClaim:
            claimName: data-pvc
        - name: backup-path
          hostPath:
            path: "${backup_folder}/filestore"
      containers:
      - name: data-backup
        image: ${REGISTRY_IP}/mekomsolutions/filestore_backup:9556d7c
        env:
          - name: FILESTORE_PATH
            value: /opt/data
        volumeMounts:
        - name: data
          mountPath: "/opt/data"
          subPath: "./"
        - name: backup-path
          mountPath: /opt/backup
      restartPolicy: Never
      nodeSelector:
        role: database
EOF

echo "⚙️ Fetch MySQL credentials"
mysql_root_user=`$kubectl get configmap mysql-configs -o json | jq '.data.MYSQL_ROOT_USER' | tr -d '"'`
mysql_root_password=`$kubectl get configmap mysql-configs -o json | jq '.data.MYSQL_ROOT_PASSWORD' | tr -d '"'`

echo "⚙️ Run MySQL backup job"
# Backup MySQL Databases

echo "Backing up OpenMRS database"
cat <<EOF | $kubectl apply -f -
apiVersion: batch/v1
kind: Job
metadata:
  name: "${OPENMRS_JOB_NAME}"
  labels:
    app: usb-backup
spec:
  template:
    spec:
      volumes:
        - name: data
          persistentVolumeClaim:
            claimName: data-pvc
        - name: backup-path
          hostPath:
            path: "${backup_folder}"
      containers:
      - name: mysql-db-backup
        image: ${REGISTRY_IP}/mekomsolutions/mysql_backup:9556d7c
        env:
          - name: DB_NAME
            value: openmrs
          - name: DB_USERNAME
            value: ${mysql_root_user}
          - name: DB_PASSWORD
            value: ${mysql_root_password}
          - name: DB_HOST
            value: mysql
        volumeMounts:
        - name: backup-path
          mountPath: /opt/backup
      restartPolicy: Never
      nodeSelector:
        role: database
EOF

# Backup PostgreSQL databases
echo "⚙️ Fetch Odoo database credentials"
odoo_user=`$kubectl get configmap odoo-configs -o json | jq '.data.ODOO_DB_USER' | tr -d '"'`
odoo_password=`$kubectl get configmap odoo-configs -o json | jq '.data.ODOO_DB_PASSWORD' | tr -d '"'`
odoo_database=`$kubectl get configmap odoo-configs -o json | jq '.data.ODOO_DB_NAME' | tr -d '"'`

echo "⚙️ Fetch OpenELIS database credentials"
openelis_user=`$kubectl get configmap openelis-db-config -o json | jq '.data.OPENELIS_DB_USER' | tr -d '"'`
openelis_password=`$kubectl get configmap openelis-db-config -o json | jq '.data.OPENELIS_DB_PASSWORD' | tr -d '"'`
openelis_database=`$kubectl get configmap openelis-db-config -o json | jq '.data.OPENELIS_DB_NAME' | tr -d '"'`


echo "⚙️ Run PostgreSQL backup jobs"
# Backup PostgreSQL Databases
echo "Backing up 'Odoo' database..."
cat <<EOF | $kubectl apply -f -
apiVersion: batch/v1
kind: Job
metadata:
  name: "${ODOO_JOB_NAME}"
  labels:
    app: usb-backup
spec:
  template:
    spec:
      volumes:
        - name: backup-path
          hostPath:
            path: "${backup_folder}"
      containers:
      - name: postgres-db-backup
        image: ${REGISTRY_IP}/mekomsolutions/postgres_backup:9556d7c
        env:
          - name: DB_HOST
            value: postgres
          - name: DB_NAME
            value: ${odoo_database}
          - name: DB_USERNAME
            value: ${odoo_user}
          - name: DB_PASSWORD
            value: ${odoo_password}
        volumeMounts:
        - name: backup-path
          mountPath: /opt/backup
      restartPolicy: Never
      nodeSelector:
        role: database
EOF

cat <<EOF | $kubectl apply -f -
apiVersion: batch/v1
kind: Job
metadata:
  name: "${OPENELIS_JOB_NAME}"
  labels:
    app: usb-backup
spec:
  template:
    spec:
      volumes:
        - name: backup-path
          hostPath:
            path: "${backup_folder}"
      containers:
      - name: postgres-db-backup
        image: ${REGISTRY_IP}/mekomsolutions/postgres_backup:9556d7c
        env:
          - name: DB_HOST
            value: postgres
          - name: DB_NAME
            value: ${openelis_database}
          - name: DB_USERNAME
            value: ${openelis_user}
          - name: DB_PASSWORD
            value: ${openelis_password}
        volumeMounts:
        - name: backup-path
          mountPath: /opt/backup
      restartPolicy: Never
      nodeSelector:
        role: database
EOF

echo "⚙️  Run logs backup job"
mkdir -p ${backup_folder}/logging
# Backup filestore
cat <<EOF | $kubectl apply -n rsyslog -f -
apiVersion: batch/v1
kind: Job
metadata:
  name: "${LOGGING_JOB_NAME}"
  labels:
    app: usb-backup
spec:
  template:
    spec:
      volumes:
        - name: data
          persistentVolumeClaim:
            claimName: logging-pvc
        - name: backup-path
          hostPath:
            path: "${backup_folder}/logging"
      containers:
      - name: data-backup
        image: ${REGISTRY_IP}/mekomsolutions/filestore_backup:9556d7c
        env:
          - name: FILESTORE_PATH
            value: /opt/data
        volumeMounts:
        - name: data
          mountPath: "/opt/data"
          subPath: "./"
        - name: backup-path
          mountPath: /opt/backup
      restartPolicy: Never
      nodeSelector:
        role: database
EOF

echo "🕐 Wait for jobs to complete... (timeout=1h)"
$kubectl wait --for=condition=complete --timeout 3600s job/${OPENMRS_JOB_NAME}
$kubectl wait --for=condition=complete --timeout 3600s job/${ODOO_JOB_NAME}
$kubectl wait --for=condition=complete --timeout 3600s job/${OPENELIS_JOB_NAME}
$kubectl wait --for=condition=complete --timeout 3600s job/${FILESTORE_JOB_NAME}
$kubectl -n rsyslog wait --for=condition=complete --timeout 3600s job/${LOGGING_JOB_NAME}
echo "✅ Restore complete."
