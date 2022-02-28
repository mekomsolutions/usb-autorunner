#!/usr/bin/env bash

kubectl="/usr/local/bin/k3s kubectl"
PWD=$(dirname "$0")
: "${NAMESPACE:=default}"

# K8s jobs nmames
OPENMRS_JOB_NAME=openmrs-db-restore
ODOO_JOB_NAME=odoo-db-restore
OPENELIS_JOB_NAME=openelis-db-restore
FILESTORE_JOB_NAME=filestore-restore

OPENMRS_SERVICE_NAME=openmrs
AUTORUNNER_WORKDIR=/opt/autorunner/workdir
ARCHIVE_PATH=${AUTORUNNER_WORKDIR}/archive
DB_RESOURCES_PATH=${AUTORUNNER_WORKDIR}/db_resources

echo "🗂  Initialize local storage folders."
# Create data volumes
mkdir -p $SSD_MOUNT_POINT/data/postgresql
mkdir -p $SSD_MOUNT_POINT/data/mysql

# Retrieve Docker registry IP address
echo "🗂  Retrieve Docker registry IP."
REGISTRY_IP=`$kubectl get svc registry-service -o json | jq '.spec.loadBalancerIP' | tr -d '"'`

# sync images to registry
echo "⚙️  Upload container images to the registry at $REGISTRY_IP..."
skopeo sync --scoped --dest-tls-verify=false --src dir --dest docker $PWD/images/docker.io $REGISTRY_IP

echo "⚙️  Apply K8s description files"
$kubectl apply -R -f $DB_RESOURCES_PATH

echo "⚙️  Wait for database services to start"
sleep 180

echo "⚙️  Fetch MySQL credentials"
MYSQL_DB_USERNAME=`$kubectl get configmap mysql-configs -o json | jq '.data.MYSQL_ROOT_USER' | tr -d '"'`
MYSQL_DB_PASSWORD=`$kubectl get configmap mysql-configs -o json | jq '.data.MYSQL_ROOT_PASSWORD' | tr -d '"'`
echo "⚙️  Fetch PostgreSQL credentials"
POSTGRES_DB_USERNAME=`$kubectl get configmap postgres-configs -o json | jq '.data.POSTGRES_USER' | tr -d '"'`
POSTGRES_DB_PASSWORD=`$kubectl get configmap postgres-configs -o json | jq '.data.POSTGRES_PASSWORD' | tr -d '"'`
echo "⚙️  Fetch Odoo database credentials"
ODOO_DB_USERNAME=`$kubectl get configmap odoo-configs -o json | jq '.data.ODOO_DB_USER' | tr -d '"'`
ODOO_DB_PASSWORD=`$kubectl get configmap odoo-configs -o json | jq '.data.ODOO_DB_PASSWORD' | tr -d '"'`
echo "⚙️  Fetch OpenELIS database credentials"
OPENELIS_DB_USERNAME=`$kubectl get configmap openelis-db-config -o json | jq '.data.OPENELIS_DB_USER' | tr -d '"'`
OPENELIS_DB_PASSWORD=`$kubectl get configmap openelis-db-config -o json | jq '.data.OPENELIS_DB_PASSWORD' | tr -d '"'`
echo "⚙️  Fetch database names"
OPENMRS_DB_NAME=`$kubectl get configmap openmrs-configs -o json | jq '.data.OPENMRS_DB_NAME' | tr -d '"'`
ODOO_DB_NAME=`$kubectl get configmap odoo-configs -o json | jq '.data.ODOO_DB_NAME' | tr -d '"'`
OPENELIS_DBNAME=`$kubectl get configmap openelis-db-config -o json | jq '.data.OPENELIS_DB_NAME' | tr -d '"'`

echo "Remove previous jobs, if exists"
$kubectl delete --ignore-not-found=true job ${OPENMRS_JOB_NAME}
$kubectl delete --ignore-not-found=true job ${ODOO_JOB_NAME}
$kubectl delete --ignore-not-found=true job ${OPENELIS_JOB_NAME}
$kubectl delete --ignore-not-found=true job ${FILESTORE_JOB_NAME}

echo "⚙️  Add ConfigMap for restore scripts"
cat <<EOF | $kubectl apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: openmrs-restore-script
data:
  openmrs_restore_script.sh: |
    #!/bin/bash
    set -eu

    mysql -u$MYSQL_DB_USERNAME -hmysql -p$MYSQL_DB_PASSWORD -e "CREATE DATABASE IF NOT EXISTS $OPENMRS_DB_NAME;"

    mysql -hmysql -u${MYSQL_DB_USERNAME} -p${MYSQL_DB_PASSWORD} ${OPENMRS_DB_NAME} -e "SOURCE /opt/openmrs.sql; SOURCE /opt/rebuild_index.sql;"
    echo "Success."
EOF

cat <<EOF | $kubectl apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: odoo-restore-script
data:
  odoo_restore_script.sh: |
    #!/bin/bash
    set -eu

    function create_user() {
      local user=\$1
      local password=\$2
      echo "Creating '\$user' user..."
      PGPASSWORD=$POSTGRES_DB_PASSWORD psql -h postgres -v ON_ERROR_STOP=1 --username "$POSTGRES_DB_USERNAME" postgres <<-EOSQL
          CREATE USER \$user WITH UNENCRYPTED PASSWORD '\$password';
          ALTER USER \$user CREATEDB;
          CREATE DATABASE $ODOO_DB_NAME;
          GRANT ALL PRIVILEGES ON DATABASE $ODOO_DB_NAME TO \$user;
    EOSQL
    }

    PGPASSWORD=$POSTGRES_DB_PASSWORD psql -h postgres --username $POSTGRES_USER postgres -tAc "SELECT 1 FROM pg_roles WHERE rolname='$ODOO_DB_USERNAME'" | grep -q 1 ||  create_user ${ODOO_DB_USERNAME} ${ODOO_DB_PASSWORD}
    set +e
    PGPASSWORD=$ODOO_DB_PASSWORD pg_restore -hpostgres -U $ODOO_DB_USERNAME -d $ODOO_DB_NAME < /opt/odoo.tar
    PGPASSWORD=$ODOO_DB_PASSWORD psql -h postgres -U postgres -c "ALTER DATABASE $ODOO_DB_NAME OWNER TO $ODOO_DB_USERNAME;"
    echo "Success."
EOF

cat <<EOF | $kubectl apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: openelis-restore-script
data:
  clinlims_restore_script.sh: |
    #!/bin/bash
    set -eu

    function create_user() {
      local user=\$1
      local password=\$2
      echo "Creating '\$user' user..."
      PGPASSWORD=$POSTGRES_DB_PASSWORD psql -h postgres -v ON_ERROR_STOP=1 --username "$POSTGRES_DB_USERNAME" postgres <<-EOSQL
          CREATE USER \$user WITH UNENCRYPTED PASSWORD '\$password';
          ALTER USER \$user CREATEDB;
          CREATE DATABASE $OPENELIS_DBNAME;
          GRANT ALL PRIVILEGES ON DATABASE $OPENELIS_DBNAME TO \$user;
    EOSQL
    }

    PGPASSWORD=$POSTGRES_DB_PASSWORD psql -h postgres --username $POSTGRES_USER postgres -tAc "SELECT 1 FROM pg_roles WHERE rolname='$OPENELIS_DB_USERNAME'" | grep -q 1 ||  create_user ${OPENELIS_DB_USERNAME} ${OPENELIS_DB_PASSWORD}
    set +e
    PGPASSWORD=$OPENELIS_DB_PASSWORD pg_restore -hpostgres -U $OPENELIS_DB_USERNAME -d $OPENELIS_DBNAME < /opt/clinlims.tar
    PGPASSWORD=$POSTGRES_DB_PASSWORD psql -h postgres -U postgres -c "ALTER DATABASE clinlims OWNER TO clinlims;"
    echo "Success."
EOF

echo "⚙️  Run MySQL restore job"
cat <<EOF | $kubectl apply -f -
apiVersion: batch/v1
kind: Job
metadata:
  name: "${OPENMRS_JOB_NAME}"
  labels:
    app: db-restore
spec:
  template:
    spec:
      affinity:
        nodeAffinity:
          requiredDuringSchedulingIgnoredDuringExecution:
            nodeSelectorTerms:
            - matchExpressions:
              - key: role
                operator: In
                values:
                - database
      volumes:
      - name: restore-storage
        hostPath:
          path: ${ARCHIVE_PATH}
      - name: restore-script
        configMap:
          name: openmrs-restore-script
      containers:
      - name: mysql-db-restore
        image: ${REGISTRY_IP}/mekomsolutions/mysql_backup:9ab7a24
        command: ["bash", "/script/openmrs_restore_script.sh"]
        env:
        volumeMounts:
        - name: restore-storage
          mountPath: /opt/
        - name: restore-script
          mountPath: /script
      restartPolicy: Never
EOF

echo "⚙️  Run PostgreSQL restore jobs"
cat <<EOF | $kubectl apply -f -
apiVersion: batch/v1
kind: Job
metadata:
  name: "${ODOO_JOB_NAME}"
  labels:
    app: db-restore
spec:
  template:
    spec:
      affinity:
        nodeAffinity:
          requiredDuringSchedulingIgnoredDuringExecution:
            nodeSelectorTerms:
            - matchExpressions:
              - key: role
                operator: In
                values:
                - database
      volumes:
      - name: restore-storage
        hostPath:
          path: ${ARCHIVE_PATH}
      - name: restore-script
        configMap:
          name: odoo-restore-script
      containers:
      - name: odoo-db-restore
        image: ${REGISTRY_IP}/mekomsolutions/postgres_backup:9ab7a24
        command: ["bash", "/script/odoo_restore_script.sh"]
        env:
        volumeMounts:
        - name: restore-storage
          mountPath: /opt/
        - name: restore-script
          mountPath: /script
      restartPolicy: Never
EOF

cat <<EOF | $kubectl apply -f -
apiVersion: batch/v1
kind: Job
metadata:
  name: "${OPENELIS_JOB_NAME}"
  labels:
    app: db-restore
spec:
  template:
    spec:
      affinity:
        nodeAffinity:
          requiredDuringSchedulingIgnoredDuringExecution:
            nodeSelectorTerms:
            - matchExpressions:
              - key: role
                operator: In
                values:
                - database
      volumes:
      - name: restore-storage
        hostPath:
          path: ${ARCHIVE_PATH}
      - name: restore-script
        configMap:
          name: openelis-restore-script
      containers:
      - name: openelis-db-restore
        image: ${REGISTRY_IP}/mekomsolutions/postgres_backup:9ab7a24
        command: ["bash", "/script/clinlims_restore_script.sh"]
        env:
        volumeMounts:
        - name: restore-storage
          mountPath: /opt/
        - name: restore-script
          mountPath: /script
      restartPolicy: Never
EOF

echo "⚙️  Run Filestore restore job"
cat <<EOF | $kubectl apply -f -
apiVersion: batch/v1
kind: Job
metadata:
  name: "${FILESTORE_JOB_NAME}"
  labels:
    app: db-restore
spec:
  template:
    spec:
      affinity:
        nodeAffinity:
          requiredDuringSchedulingIgnoredDuringExecution:
            nodeSelectorTerms:
            - matchExpressions:
              - key: role
                operator: In
                values:
                - database
      volumes:
      - name: restore-storage
        hostPath:
          path: ${ARCHIVE_PATH}
      - name: filestore
        persistentVolumeClaim:
          claimName: data-pvc
      containers:
      - name: filestore-db-restore
        image: ${REGISTRY_IP}/mekomsolutions/postgres_backup:9ab7a24
        command: ["unzip"]
        args: ["/opt/filestore.zip", "-o", "-d", "/filestore"]
        env:
        volumeMounts:
        - name: restore-storage
          mountPath: /opt
        - name: filestore
          mountPath: /filestore
      restartPolicy: Never
EOF

echo "🕐 Wait for jobs to complete... (timeout=1h)"
$kubectl wait --for=condition=complete --timeout 3600s job/${FILESTORE_JOB_NAME}
$kubectl wait --for=condition=complete --timeout 3600s job/${ODOO_JOB_NAME}
$kubectl wait --for=condition=complete --timeout 3600s job/${OPENMRS_JOB_NAME}
$kubectl wait --for=condition=complete --timeout 3600s job/${OPENELIS_JOB_NAME}
echo "OpenMRS database restore Completed."

echo "✅ Done."
