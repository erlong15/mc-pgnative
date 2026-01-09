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


## Установим prometheus stack
helm install prom oci://ghcr.io/prometheus-community/charts/kube-prometheus-stack

## Раскатка базовых алертов
kubectl apply -f \
  https://raw.githubusercontent.com/cloudnative-pg/cloudnative-pg/main/docs/src/samples/monitoring/prometheusrule.yaml

