-- опционально 
  ## Устанавливаем OLM
  operator-sdk olm install

  ## Устанавливаем pgnative оператор
  kubectl create -f https://operatorhub.io/install/cloudnative-pg.yaml

  ## Следим за установкой оператора
  kubectl get csv -n operators



---

## установка через хелм
helm repo add cnpg https://cloudnative-pg.github.io/charts
helm upgrade --install cnpg \
  --namespace cnpg-system \
  --create-namespace \
  cnpg/cloudnative-pg


## подключим клиента
export PSQL_CONNECTION_STRING=postgres://app:password@cluster-example-rw:5432/app?sslmode=require
kubectl run -ti --rm --image=alpine/psql psql -- $PSQL_CONNECTION_STRING

## Создадим схему данных и проведем небольшие нагрузочные тесты
kubectl port-forward svc/cluster-example-rw 5432:5432
psql "postgres://app:password@localhost:5432/app?sslmode=allow" -f db.sql
psql "postgres://app:password@localhost:5432/app?sslmode=allow" -f load_generator.sql


pgbench "postgres://app:password@localhost:5432/app?sslmode=allow" -f load_queries.sql -c 10 -j 2 -T 300

## Установим prometheus stack
helm install prom oci://ghcr.io/prometheus-community/charts/kube-prometheus-stack

## Раскатим pod monitor
kubectl apply -f podmonitor.yaml

## Проверим сборку метрик
kubectl port-forward svc/prom-kube-prometheus-stack-prometheus 9090


## Раскатка базовых алертов
kubectl apply -f \
  https://raw.githubusercontent.com/cloudnative-pg/cloudnative-pg/main/docs/src/samples/monitoring/prometheusrule.yaml

## Импортируем дашборд
https://raw.githubusercontent.com/cloudnative-pg/grafana-dashboards/refs/heads/main/charts/cluster/grafana-dashboard.json


## cnpg
brew install kubectl-cnpg
kubectl cnpg status cluster-example
kubectl cnpg psql cluster-example -- -qAt -c 'SELECT version()'

kubectl cnpg promote [cluster] [new_primary]
kubectl cnpg restart [cluster] [current_primary]

## установка barman-plugin
helm install \
  cert-manager jetstack/cert-manager \
  --namespace cert-manager \
  --create-namespace \
  --version v1.19.2 \
  --set crds.enabled=true

cmctl check api

kubectl apply -f \
        https://github.com/cloudnative-pg/plugin-barman-cloud/releases/download/v0.10.0/manifest.yaml

kubectl rollout status deployment \
  -n cnpg-system barman-cloud

## создание бэкапа
kubectl cnpg backup cluster-example --method plugin --plugin-name barman-cloud.cloudnative-pg.io

kubectl apply -f /Users/lucky/projects/masterclasses/mc-pgnative/pg/backup.yaml

## проверка статуса базы в том числе архивирование WAL
kubectl cnpg status cluster-example

