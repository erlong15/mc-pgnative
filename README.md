## Устанавливаем OLM
operator-sdk olm install

## Устанавливаем pgnative оператор
kubectl create -f https://operatorhub.io/install/cloudnative-pg.yaml

## Следим за установкой оператора
kubectl get csv -n operators

## Установим prometheus stack
helm install prom oci://ghcr.io/prometheus-community/charts/kube-prometheus-stack

## Раскатка базовых алертов
kubectl apply -f \
  https://raw.githubusercontent.com/cloudnative-pg/cloudnative-pg/main/docs/src/samples/monitoring/prometheusrule.yaml

